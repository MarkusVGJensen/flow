#!/bin/sh
# PostToolUse on Bash and PowerShell: after a `git push` of a branch that has an open MR, tells
# Claude to watch the pipeline that push started, as /flow:watch-pipeline does. The watching itself
# stays the command's: a waiter in the background that costs nothing until CI finishes, within the
# command's limits. A push of a branch without an open MR, such as the commits gate's before the MR
# exists, says nothing. Always exits 0: it never blocks, and an error only means no reminder.

set -u
. "$(dirname "$0")/command-dir.sh"
payload=$(cat | tr '\n' ' ')

hook_command "$payload" | grep -Eq "$(git_call push)" || exit 0
here=$(command_dir "$payload" push) && cd "$here" 2>/dev/null || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ "$branch" != HEAD ] || exit 0

config=""
if [ -f "$here/.claude/flow.json" ]; then
  config="$here/.claude/flow.json"
elif [ -f "$HOME/.claude/flow.local.json" ]; then
  config="$HOME/.claude/flow.local.json"
fi
[ -n "$config" ] || exit 0
value() { grep -Eo "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$config" | head -n 1 | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'; }
forge=$(value forge) project=$(value project)
[ -n "$project" ] && [ "$branch" != "$(value defaultTarget)" ] || exit 0

case "$forge" in
  glab)
    enc=$(printf '%s' "$project" | sed 's|/|%2F|g')
    mr=$(glab api "projects/$enc/merge_requests?state=opened&source_branch=$branch" 2>/dev/null \
      | grep -o '"iid":[0-9]*' | head -n 1 | sed 's/.*://')
    ;;
  gh)
    mr=$(gh pr view "$branch" --repo "$project" --json number,state -q 'select(.state == "OPEN") | .number' 2>/dev/null)
    ;;
  *) exit 0 ;;
esac
[ -n "$mr" ] || exit 0

msg="flow: this push updated $branch, which has open MR $mr, so its pipeline starts now. Unless a waiter for MR $mr already runs in this session, or the user said not to watch CI, watch it as /flow:watch-pipeline $mr describes (the flow:watch-pipeline skill with $mr)."
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$msg"
exit 0
