#!/bin/sh
# Blocks `git commit` when tracked source files are newer than the formatter stamp.
# Exit 0 allows the commit; exit 2 blocks it and shows stderr to Claude.
#
# The stamp is written by the flow's format step:  touch "$(git rev-parse --git-dir)/flow-formatted"

set -u

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0   # not a repo: not our business
gitdir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
stamp="$gitdir/flow-formatted"

# Only source files matter. Data, docs and generated output are not the formatter's business.
changed=$( { git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null; } \
  | sort -u \
  | grep -Ei '\.(c|cc|cpp|cxx|h|hh|hpp|hxx|m|mm|swift|py|ps1|sh|js|ts|tsx|java|kt|rs|go)$' ) || true

[ -z "$changed" ] && exit 0

if [ ! -f "$stamp" ]; then
  echo "Formatting has not run in this worktree. Run the project's formatter (verify.format), then:" >&2
  echo "  touch \"$gitdir/flow-formatted\"" >&2
  exit 2
fi

stale=""
for f in $changed; do
  [ -f "$root/$f" ] || continue
  if [ "$root/$f" -nt "$stamp" ]; then
    stale="$stale $f"
  fi
done

if [ -n "$stale" ]; then
  echo "These files changed after the formatter last ran:" >&2
  for f in $stale; do echo "  $f" >&2; done
  echo "Run the project's formatter (verify.format), then: touch \"$gitdir/flow-formatted\"" >&2
  echo "Formatting rewrites every mtime, so run it LAST — after the gate build, not before." >&2
  exit 2
fi

exit 0
