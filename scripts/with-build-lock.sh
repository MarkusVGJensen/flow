#!/bin/sh
# Runs one build command while holding the worktree's build lock, so builds
# take turns on the build tree instead of corrupting it: flow's early build,
# the tester's and the gate's, and Helm's configure and background builds,
# which hold the same lock. Waits, without a model in the loop, while someone
# else holds it.
#
#   with-build-lock.sh <command> [args...]
#
# Run from inside the worktree. Exits with the command's own status.
#
# The lock is `<git dir>/build.lock`: a folder, because making one is atomic,
# holding an `owner` file that the holder rewrites every 30 seconds while it
# builds. A lock whose `owner` has not changed for two minutes belonged to
# something that died and is taken over. Helm's `src-tauri/src/build_lock.rs`
# follows the same rules; change both together.

[ $# -gt 0 ] || { echo "usage: with-build-lock.sh <command> [args...]"; exit 2; }

git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exec "$@"
lock="$git_dir/build.lock"
owner="flow $$ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
stale=120

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

age() {
  m=$(mtime "$lock/owner") || m=$(mtime "$lock") || { echo 0; return; }
  echo $(( $(date +%s) - m ))
}

told=""
until mkdir "$lock" 2>/dev/null; do
  if [ "$(age)" -ge "$stale" ]; then
    rm -rf "$lock"
    continue
  fi
  if [ -z "$told" ]; then
    echo "waiting: $(cat "$lock/owner" 2>/dev/null || echo 'another build') holds the build lock"
    told=1
  fi
  sleep 5
done
printf '%s' "$owner" > "$lock/owner"

mine() { [ "$(cat "$lock/owner" 2>/dev/null)" = "$owner" ]; }

( while sleep 30; do mine || exit 0; printf '%s' "$owner" > "$lock/owner"; done ) &
keeper=$!

release() {
  kill "$keeper" 2>/dev/null
  mine && rm -rf "$lock"
}
trap release EXIT
trap 'exit 130' INT TERM

"$@"
code=$?
exit $code
