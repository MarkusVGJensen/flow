#!/usr/bin/env node
// Puts the compile_commands.json clangd reads at a checkout's root, for compile-commands.sh.
//
//   node compile-commands.mjs <root> [hub]
//
// CMake writes the database into the build tree (build/<preset>, out/build/<preset>), where clangd
// never looks. The root gets the checkout's own newest one when it has a build tree, and until then
// the Hub's, with its source paths moved to this checkout and its paths into the Hub's build tree
// (installed packages, generated headers) kept. The Hub is <hub>, else HELM_HUB, else a worktree of
// the repository named `hub`. A copy the repository tracks is never touched, and one nothing ignores
// is added to the repository's info/exclude first.
//
// The same as Helm's compdb.rs, byte for byte, so the two never rewrite each other's copy. Prints
// `own <path>` or `borrowed <path>` when it wrote the root copy, nothing when it was current or
// there was nothing to copy. Exits 1 on an error.

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative } from "node:path";

const FILE = "compile_commands.json";

const git = (cwd, ...args) => {
  const r = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8" });
  return { code: r.status, out: (r.stdout || "").trim() };
};

const mtime = (p) => {
  try {
    return statSync(p).mtimeMs;
  } catch {
    return null;
  }
};

/** The newest database in the folder's build trees, if any. */
function newest(folder) {
  const dirs = [join(folder, "build")];
  for (const parent of [join(folder, "build"), join(folder, "out", "build")]) {
    try {
      for (const e of readdirSync(parent, { withFileTypes: true })) if (e.isDirectory()) dirs.push(join(parent, e.name));
    } catch {
      // No such tree.
    }
  }
  let best = null;
  for (const d of dirs) {
    const p = join(d, FILE);
    const t = mtime(p);
    if (t !== null && (!best || t > best.t)) best = { p, t };
  }
  return best?.p ?? null;
}

const sep = (c) => c === "/" || c === "\\";
const same = (a, b) => (sep(a) && sep(b)) || a.toLowerCase() === b.toLowerCase();
const trimSeps = (s) => s.replace(/[\\/]+$/, "");

/** Whether `pat` is spelled at `at`, separators and ASCII case aside, and ends a path component. */
function pathAt(hay, at, pat) {
  const end = at + pat.length;
  if (end > hay.length) return false;
  for (let i = 0; i < pat.length; i++) if (!same(hay[at + i], pat[i])) return false;
  return end === hay.length || !/[A-Za-z0-9_.-]/.test(hay[end]);
}

/** `text` with every path under `from` moved under `to`, except those under `keep`. */
function movePaths(text, from, keep, to) {
  if (!from) return text;
  let out = "";
  let i = 0;
  while (i < text.length) {
    // No check before the match: a flag runs straight into its path, as in `-ID:\src`.
    if (pathAt(text, i, from) && !pathAt(text, i, keep)) {
      const slash = [...text.slice(i, i + from.length)].find(sep) ?? "/";
      out += [...to].map((c) => (sep(c) ? slash : c)).join("");
      i += from.length;
    } else {
      out += text[i++];
    }
  }
  return out;
}

function moveValue(v, from, keep, to) {
  if (typeof v === "string") return movePaths(v, from, keep, to);
  if (Array.isArray(v)) return v.map((x) => moveValue(x, from, keep, to));
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, moveValue(x, from, keep, to)]));
  return v;
}

/** The source folder as the database spells it: an entry's directory is the build tree, `rel` below it. */
function spelledRoot(entries, rel) {
  const dir = trimSeps(entries[0]?.directory ?? "");
  rel = trimSeps(rel);
  const cut = dir.length - rel.length - 1;
  if (!dir || cut < 0 || !sep(dir[cut])) return null;
  const tail = dir.slice(cut + 1);
  return [...tail].every((c, i) => same(c, rel[i])) ? dir.slice(0, cut) : null;
}

/** serde_json's pretty form: two-space indent and, without preserve_order, sorted keys. */
function sorted(v) {
  if (Array.isArray(v)) return v.map(sorted);
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])]));
  return v;
}

function writeIfChanged(target, bytes) {
  try {
    if (readFileSync(target).equals(bytes)) return false;
  } catch {
    // No copy yet.
  }
  const tmp = `${target}.flow-tmp`;
  writeFileSync(tmp, bytes);
  renameSync(tmp, target);
  return true;
}

/** Whether the root copy may be written: never over a tracked one; an unignored one is excluded first. */
function mayWrite(root) {
  if (git(root, "ls-files", "--error-unmatch", "--", FILE).code === 0) return false;
  if (git(root, "check-ignore", "-q", "--", FILE).code === 0) return true;
  const common = git(root, "rev-parse", "--path-format=absolute", "--git-common-dir");
  if (common.code !== 0) return false;
  const exclude = join(common.out, "info", "exclude");
  const line = `/${FILE}`;
  const old = existsSync(exclude) ? readFileSync(exclude, "utf8") : "";
  if (!old.split(/\r?\n/).some((l) => l.trim() === line)) {
    mkdirSync(dirname(exclude), { recursive: true });
    appendFileSync(exclude, `${old === "" || old.endsWith("\n") ? "" : "\n"}${line}\n`);
  }
  return true;
}

/** The Hub: the one named, else a worktree of this repository whose folder is `hub`. */
function findHub(root, named) {
  if (named) return named;
  const list = git(root, "worktree", "list", "--porcelain");
  if (list.code !== 0) return null;
  const paths = list.out.split(/\r?\n/).filter((l) => l.startsWith("worktree ")).map((l) => l.slice(9));
  return paths.find((p) => basename(p).toLowerCase() === "hub") ?? null;
}

const samePath = (a, b) => trimSeps(a).replace(/\\/g, "/").toLowerCase() === trimSeps(b).replace(/\\/g, "/").toLowerCase();

function main() {
  const [root, named = process.env.HELM_HUB || ""] = process.argv.slice(2);
  if (!root) {
    console.error("usage: node compile-commands.mjs <root> [hub]");
    process.exit(2);
  }
  const target = join(root, FILE);
  const own = newest(root);
  if (own) {
    // A copy written after the build tree last changed is current.
    const copy = mtime(target);
    if (copy !== null && copy > mtime(own)) return;
    if (!mayWrite(root)) return;
    if (writeIfChanged(target, readFileSync(own))) console.log(`own ${own}`);
    return;
  }
  const hub = findHub(root, named);
  if (!hub || samePath(hub, root)) return;
  const source = newest(hub);
  if (!source || !mayWrite(root)) return;
  const db = JSON.parse(readFileSync(source, "utf8"));
  const rel = relative(hub, dirname(source)) || "build";
  const from = spelledRoot(Array.isArray(db) ? db : [], rel) ?? trimSeps(hub);
  const slash = from.includes("\\") ? "\\" : "/";
  const keep = `${from}${slash}${trimSeps(rel)}`;
  const moved = moveValue(db, from, keep, trimSeps(root));
  if (writeIfChanged(target, Buffer.from(JSON.stringify(sorted(moved), null, 2)))) console.log(`borrowed ${source}`);
}

try {
  main();
} catch (error) {
  console.error(String(error?.message ?? error));
  process.exit(1);
}
