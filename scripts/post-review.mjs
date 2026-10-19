#!/usr/bin/env node
// Posts a review's notes file to a GitLab merge request as draft notes, each anchored to its lines:
// a comment about several lines as a multi-line range, a comment about one line on that line.
// Nothing is ever posted without a position, so a review never becomes a general comment.
//
//   node post-review.mjs <project> <notes.json> [glab] [--dry-run]
//
// --dry-run reads the diff and prints each note's anchor and position without posting anything.
//
// The notes file is the one /flow:review-mr writes: mr, base_sha, start_sha, head_sha, and notes
// of {path, old_path?, start_line?, line, side, body}. The line numbers belong to the diff between
// those SHAs. Prints one line per note and exits 1 when any note failed; a failed note is not
// retried here, so run it on a file holding only the failures to try them again.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const argv = process.argv.slice(2);
const dryRun = argv.includes("--dry-run");
const [project, notesPath, glab = "glab"] = argv.filter((a) => a !== "--dry-run");
if (!project || !notesPath) {
  console.error("usage: node post-review.mjs <project> <notes.json> [glab] [--dry-run]");
  process.exit(2);
}

const file = JSON.parse(readFileSync(notesPath, "utf8"));
const iid = Number(file.mr);
const refs = { base_sha: file.base_sha, start_sha: file.start_sha || file.base_sha, head_sha: file.head_sha };
if (!iid || !refs.base_sha || !refs.head_sha) {
  console.error("The notes file needs mr, base_sha and head_sha.");
  process.exit(2);
}
const enc = encodeURIComponent(project);

function api(method, path, body) {
  const args = ["api", "--method", method, `projects/${enc}/${path}`];
  // Without the content type GitLab reads the body as a form and answers 415.
  if (body !== undefined) args.push("-H", "Content-Type: application/json", "--input", "-");
  const r = spawnSync(glab, args, { input: body === undefined ? undefined : JSON.stringify(body), encoding: "utf8" });
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error((r.stderr || r.stdout || `glab exited with ${r.status}`).trim());
  return r.stdout.trim() ? JSON.parse(r.stdout) : null;
}

// ---- the MR's diff, as GitLab numbers it -------------------------------------------------------

/**
 * The diff the notes were written against: the MR version whose head is the file's head_sha. The
 * MR may have moved since the review; its current diff would then number the lines differently.
 */
function fetchDiffs() {
  let versions = null;
  try {
    versions = api("GET", `merge_requests/${iid}/versions`);
  } catch {
    // Without the versions endpoint, only the current diff can be had.
  }
  if (Array.isArray(versions) && versions.length) {
    const version = versions.find((v) => v.head_commit_sha === refs.head_sha);
    if (!version) {
      console.error(`!${iid} has no version with head ${refs.head_sha}: the notes cannot be placed. Review the current head again.`);
      process.exit(2);
    }
    if (version !== versions[0]) {
      console.log(`warning: !${iid} has moved since this review (now at ${versions[0].head_commit_sha.slice(0, 8)}); the comments are anchored on the reviewed version and GitLab may show them as outdated`);
    }
    return api("GET", `merge_requests/${iid}/versions/${version.id}`).diffs ?? [];
  }
  const all = [];
  try {
    for (let page = 1; ; page++) {
      const list = api("GET", `merge_requests/${iid}/diffs?per_page=50&page=${page}`);
      if (!Array.isArray(list) || list.length === 0) break;
      all.push(...list);
      if (list.length < 50) break;
    }
    return all;
  } catch {
    // Servers before GitLab 15.7 have only the older endpoint.
    return api("GET", `merge_requests/${iid}/changes`).changes ?? [];
  }
}

/**
 * Every line of every hunk with the counters GitLab's own diff parser keeps: an added line has
 * the old-side number the next unchanged line would have, a removed one the new-side number.
 * Those two numbers are what `line_code` is built from.
 */
function parseHunks(diff) {
  const hunks = [];
  let hunk = null, oldNo = 0, newNo = 0;
  for (const raw of (diff ?? "").replace(/\n$/, "").split("\n")) {
    const head = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(raw);
    if (head) {
      oldNo = Number(head[1]);
      newNo = Number(head[2]);
      hunk = [];
      hunks.push(hunk);
      continue;
    }
    if (!hunk || raw.startsWith("\\")) continue;
    const kind = raw[0] === "+" ? "add" : raw[0] === "-" ? "del" : raw[0] === " " || raw === "" ? "ctx" : null;
    if (!kind) continue;
    hunk.push({
      kind,
      oldNo: kind === "add" ? null : oldNo,
      newNo: kind === "del" ? null : newNo,
      oldPos: oldNo,
      newPos: newNo,
    });
    if (kind !== "add") oldNo++;
    if (kind !== "del") newNo++;
  }
  return hunks;
}

const numberOn = (point, side) => (side === "old" ? point.oldNo : point.newNo);

function findPoints(hunks, note) {
  for (const points of hunks) {
    const end = points.find((p) => numberOn(p, note.side) === note.line);
    if (!end) continue;
    const start = note.start_line ? points.find((p) => numberOn(p, note.side) === note.start_line) : null;
    return { start: start && points.indexOf(start) < points.indexOf(end) ? start : null, end };
  }
  return null;
}

/** The single-line fields: an added line is new-side only, a removed one old-side only, an unchanged one both. */
function lineFields(p) {
  if (p.kind === "add") return { new_line: p.newNo };
  if (p.kind === "del") return { old_line: p.oldNo };
  return { old_line: p.oldNo, new_line: p.newNo };
}

function rangePoint(hash, p) {
  return {
    line_code: `${hash}_${p.oldPos}_${p.newPos}`,
    ...(p.kind === "add" ? { type: "new" } : p.kind === "del" ? { type: "old" } : {}),
    ...lineFields(p),
  };
}

function payload(note, diff, ranged) {
  const newPath = diff?.new_path ?? note.path;
  const position = {
    position_type: "text",
    ...refs,
    new_path: newPath,
    old_path: diff?.old_path ?? note.old_path ?? newPath,
  };
  const points = diff ? findPoints(parseHunks(diff.diff), note) : null;
  if (!points) {
    // A line the diff does not hold (a collapsed or very large file): its number alone, and GitLab decides.
    position[note.side === "old" ? "old_line" : "new_line"] = note.line;
  } else {
    Object.assign(position, lineFields(points.end));
    if (ranged && points.start) {
      const hash = createHash("sha1").update(newPath).digest("hex");
      position.line_range = { start: rangePoint(hash, points.start), end: rangePoint(hash, points.end) };
    }
  }
  return { note: note.body, position, ranged: Boolean(ranged && points?.start) };
}

// ---- posting -----------------------------------------------------------------------------------

const diffs = fetchDiffs();
const diffOf = (note) => diffs.find((d) => d.new_path === note.path) ?? diffs.find((d) => d.old_path === note.path);
const post = (body) => api("POST", `merge_requests/${iid}/draft_notes`, { note: body.note, position: body.position });

let failed = 0;
const notes = [...(file.notes ?? [])].sort((a, b) => String(a.path).localeCompare(String(b.path)) || a.line - b.line);
for (const raw of notes) {
  const note = { ...raw, side: raw.side === "old" ? "old" : "new", line: Number(raw.line), start_line: raw.start_line ? Number(raw.start_line) : null };
  const where = `${note.path}:${note.start_line ? `${note.start_line}-` : ""}${note.line}`;
  if (!note.path || !note.line || !String(note.body ?? "").trim()) {
    console.log(`SKIPPED ${where || "(no path)"}: a note needs a path, a line and a body; nothing is posted without them`);
    failed++;
    continue;
  }
  const diff = diffOf(note);
  try {
    const wanted = payload(note, diff, true);
    if (dryRun) {
      const anchor = wanted.ranged ? "range" : diff ? "line" : "line, file not in the diff";
      console.log(`would   ${where} (${anchor}) ${JSON.stringify(wanted.position)}`);
      continue;
    }
    if (!wanted.ranged) {
      post(wanted);
      console.log(`ok      ${where}${note.start_line ? " (on its last line: the range is not in one hunk)" : ""}`);
      continue;
    }
    let posted;
    try {
      posted = post(wanted);
    } catch {
      post(payload(note, diff, false));
      console.log(`ok      ${where} (on its last line: GitLab refused the range)`);
      continue;
    }
    if (posted?.position?.line_range) {
      console.log(`ok      ${where} (range)`);
      continue;
    }
    // Accepted but the range dropped: post it again on its last line, which still shows the lines above.
    api("DELETE", `merge_requests/${iid}/draft_notes/${posted.id}`);
    post(payload(note, diff, false));
    console.log(`ok      ${where} (on its last line: GitLab dropped the range)`);
  } catch (error) {
    console.log(`FAILED  ${where}: ${String(error.message ?? error).split("\n")[0]}`);
    failed++;
  }
}
console.log(`${notes.length - failed} of ${notes.length} ${dryRun ? "would be posted" : "posted"} as drafts on !${iid}`);
process.exit(failed ? 1 : 0);
