#!/bin/sh
# Guards on every Bash call, for the two mistakes that are expensive and easy to repeat.
# Reads the hook payload on stdin and checks the command line by line, so a multi-line command is
# checked whole. Exit 0 allows; exit 2 blocks and shows stderr to Claude.

set -u
. "$(dirname "$0")/command-dir.sh"
payload=$(cat | tr '\n' ' ')
cmd=$(hook_command "$payload")

# 1. A force push without a lease can overwrite someone else's work. --force-with-lease is allowed;
#    it is what /flow:watch-pipeline uses after tagging a backup. `git push` counts only where a
#    command starts (a line's start, or after ; & | or a parenthesis), so a commit message that
#    mentions it mid-sentence is not blocked. A `+` refspec (`git push origin +main`) is a force push too.
push='(^|[;&|(])[[:space:]]*git +push[^;&|]*'
if printf '%s\n' "$cmd" | grep -Eq "$push"' (--force|-f)([ ;&|)]|$)' \
   || printf '%s\n' "$cmd" | grep -Eq "$push"' \+[^ ]'; then
  echo "Blocked: 'git push --force' without a lease." >&2
  echo "Use 'git push --force-with-lease' after 'git tag backup/<branch>-<stamp>', and only on your own branch." >&2
  echo "If the lease fails, the remote moved: stop and report, do not retry." >&2
  exit 2
fi

# 2. A tree-wide formatter run rewrites every mtime, and a parallel formatter that fails midway can
#    leave files it never meant to touch modified or damaged. Per-file runs are fine. Which script that is belongs to the project, so the pattern comes from the flow config:
#    `verify.formatGuard`, an extended regex matched against the command. No value, no guard.
#    The config is looked up where the command acts, which a leading `cd` may have moved.
here=$(command_dir "$payload")
config=""
if [ -f "$here/.claude/flow.json" ]; then
  config="$here/.claude/flow.json"
elif [ -f "$HOME/.claude/flow.local.json" ]; then
  config="$HOME/.claude/flow.local.json"
fi
guard=""
if [ -n "$config" ]; then
  guard=$(grep -Eo '"formatGuard"[[:space:]]*:[[:space:]]*"[^"]*"' "$config" | head -n 1 | sed -E 's/^"formatGuard"[[:space:]]*:[[:space:]]*"//; s/"$//')
fi
# Only a run counts: the pattern at the start of a command, after any VAR=value prefixes and an
# interpreter such as `python` or `pwsh -File`. A grep, ls or cat that merely names the script, and
# its --help or --version, pass.
runs=$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n' \
  | sed -E -e 's/^[[:space:]]*//' -e ':a' -e 's/^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^ ]*) +//' -e 'ta')
interp='((python[0-9.]*|py|pwsh|powershell|sh|bash|perl|node)(\.exe)?( +-[^ ]+)* +)?'
if [ -n "$guard" ] \
   && printf '%s\n' "$runs" | grep -Ev -- '--help|--version' | grep -Eq "^$interp[\"'&]?[^ \"'()]*($guard)" \
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
