# Sourced by the hooks. Works out which directory a Bash call really acts in.
#
# A hook runs in the session's directory, but one Bash call can move: `cd <worktree> && git commit`
# or `git -C <worktree> commit`. Checking the session's directory then checks the wrong repository.
#
#   hook_command <payload>   prints the command string, JSON escapes undone
#   hook_cwd <payload>       prints the payload's cwd, or the hook's own directory
#   command_dir <payload> [sub]
#                            prints the directory the call acts in: hook_cwd, moved by every `cd`
#                            before the `git <sub>` call (or in the whole command, without <sub>),
#                            then by that call's `git -C`. Quoted paths and a leading ~ are handled.
#                            Fails when a cd target does not exist.

json_string() {   # json_string <payload> <key>
  printf '%s' "$1" \
    | sed -nE 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"(([^"\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

hook_command() { json_string "$1" command; }

hook_cwd() {
  d=$(json_string "$1" cwd)
  [ -n "$d" ] && [ -d "$d" ] && { printf '%s' "$d"; return; }
  pwd
}

unquote() {   # strips one layer of matching quotes and expands a leading ~
  u=$(printf '%s' "$1" | sed -E "s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/")
  case "$u" in "~"|"~/"*) u="$HOME${u#\~}" ;; esac
  printf '%s' "$u"
}

ARG='("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ;&|()]+)'

git_call() {   # git_call <subcommand>: regex for a git call to it, optionally with -C <dir>
  printf '%s' "(^|[;&|(])[[:space:]]*git( +-C +$ARG)? +$1( |\$)"
}

command_dir() {   # command_dir <payload> [git subcommand]
  cmd=$(hook_command "$1")
  dir=$(hook_cwd "$1")
  # With a subcommand, only what runs before that git call moves it, plus its own -C.
  pre=$cmd call=""
  if [ -n "${2:-}" ]; then
    pre=$(printf '%s' "$cmd" | sed -E "s/$(git_call "$2").*//")
    call=$(printf '%s' "$cmd" | grep -oE "$(git_call "$2")" | head -n 1)
  fi
  # Every cd, in order, each relative to where the one before left off.
  cds=$(printf '%s' "$pre" | grep -oE "(^|[;&|(])[[:space:]]*cd +$ARG" \
        | sed -E 's/^[;&|(]?[[:space:]]*cd +//')
  while IFS= read -r to; do
    [ -n "$to" ] || continue
    to=$(unquote "$to")
    dir=$(cd "$dir" 2>/dev/null && cd "$to" 2>/dev/null && pwd) || return 1
  done <<EOF
$cds
EOF
  c=$(printf '%s' "$call" | grep -oE "git +-C +$ARG" | sed -E 's/^git +-C +//')
  if [ -n "$c" ]; then
    c=$(unquote "$c")
    dir=$(cd "$dir" 2>/dev/null && cd "$c" 2>/dev/null && pwd) || return 1
  fi
  printf '%s' "$dir"
}
