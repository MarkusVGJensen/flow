#!/bin/sh
# SessionStart: gives a C/C++ checkout the compile_commands.json clangd reads at its root, then
# checks it. The root gets the build tree's own copy when it is newer, and without a build tree the
# Hub's (HELM_HUB, else a worktree named hub) with its paths moved here; compile-commands.mjs does
# that, the same way Helm does. Without it the LSP tool parses every file with guessed flags and its
# answers mislead, so what could not be fixed is told to Claude up front. Whatever this prints is
# added to the session's context. Always exits 0: it never blocks.

set -u
. "$(dirname "$0")/command-dir.sh"
payload=$(cat | tr '\n' ' ')

cd "$(hook_cwd "$payload")" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only CMake projects are this hook's business; anything else has no compile database to find.
[ -f "$root/CMakeLists.txt" ] || exit 0

db="$root/compile_commands.json"

# Before clangd first looks: one that finds none looks again only after half a minute.
if command -v node >/dev/null 2>&1; then
  case "$(node "$(dirname "$0")/compile-commands.mjs" "$root" 2>/dev/null)" in
    own\ *) echo "flow: copied this checkout's build-tree compile_commands.json to $root." ;;
    borrowed\ *)
      echo "flow: wrote the Hub's compile_commands.json to $root, its paths moved to this checkout, until this checkout is configured."
      echo "Files new on this branch are not in it; clangd guesses their flags from a neighbour."
      ;;
  esac
fi

# A file path written the way a compile database writes it: forward slashes, lower case.
norm() { printf '%s' "$1" | sed -e 's|\\\\|/|g' -e 's|\\|/|g' | tr 'A-Z' 'a-z'; }

if [ ! -f "$db" ]; then
  # A build tree may already hold one; clangd only looks at the root and in build/.
  found=$(find "$root/build" -maxdepth 3 -name compile_commands.json 2>/dev/null | head -n 1)
  echo "flow: no compile_commands.json at $root."
  echo "clangd guesses the compile flags here, so LSP answers are unreliable: headers reported missing, types shown as int, references missing."
  if [ -n "$found" ]; then
    echo "The build tree has one at $found. Copying it to the root would give the LSP real flags; ask the user before doing so."
  else
    echo "No build tree has one yet; it appears after the project is configured."
  fi
  echo "Until then, use Grep and Glob for symbols, and treat any LSP result as a hint."
  exit 0
fi

# Present, but written for another checkout: a copy carried over, or a borrowed one never moved.
first=$(grep -m 1 -o '"file"[[:space:]]*:[[:space:]]*"[^"]*"' "$db" | sed -E 's/^"file"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$first" ]; then
  echo "flow: $db lists no files. LSP answers are unreliable until the project is configured again."
  exit 0
fi
case "$(norm "$first")" in
  "$(norm "$root")"/*) ;;
  *)
    echo "flow: $db describes another checkout (its first file is $first)."
    echo "LSP answers may point outside this worktree. Treat them as hints and confirm with Grep."
    ;;
esac
exit 0
