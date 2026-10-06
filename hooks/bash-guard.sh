#!/bin/sh
# Guards on every Bash call, for the two mistakes that are expensive and easy to repeat.
# Reads the hook payload on stdin; the command is inspected as raw JSON text, which is enough for a
# pattern check. Exit 0 allows; exit 2 blocks and shows stderr to Claude.

set -u
payload=$(cat | tr '\n' ' ')

# 1. A force push without a lease can overwrite someone else's work. --force-with-lease is allowed;
#    it is what /flow:watch-pipeline uses after tagging a backup.
if printf '%s' "$payload" | grep -Eq 'git +push[^"]* (--force|-f)( |\\|"|$)'; then
  echo "Blocked: 'git push --force' without a lease." >&2
  echo "Use 'git push --force-with-lease' after 'git tag backup/<branch>-<stamp>', and only on your own branch." >&2
  echo "If the lease fails, the remote moved: stop and report, do not retry." >&2
  exit 2
fi

# 2. The tree-wide formatter is destructive when its worker pool fails (it has truncated untouched
#    files to 0 bytes) and rewrites every mtime. Per-file runs are fine. A tree-wide run needs the
#    checks below and an explicit acknowledgement so it cannot be reached by reflex.
if printf '%s' "$payload" | grep -Eq 'enforce-source-file-formatting' \
   && ! printf '%s' "$payload" | grep -Eq -- '--file' \
   && ! printf '%s' "$payload" | grep -Eq 'FLOW_TREEWIDE_OK=1'; then
  echo "Blocked: tree-wide formatter run." >&2
  echo "Prefer the per-file form: ... --file <path>, once per changed file." >&2
  echo "If the whole tree is needed (once, before the push): check free disk space first, never run it in a loop," >&2
  echo "and afterwards 'git status' for files OUTSIDE your change set and restore them with 'git checkout -- <file>'." >&2
  echo "When you have read this, prefix the command with FLOW_TREEWIDE_OK=1 to run it." >&2
  exit 2
fi

exit 0
