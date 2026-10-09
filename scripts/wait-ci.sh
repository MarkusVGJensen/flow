#!/bin/sh
# Waits for an MR's pipeline (GitLab) or a PR's checks (GitHub) without a
# model in the loop: it polls on its own, prints one line each time the
# status changes, and exits when CI has finished, so the session spends no
# tokens while CI runs. /flow:watch-pipeline starts it in the background.
#
#   wait-ci.sh <glab|gh> <project> <mr-number> [poll-seconds] [max-minutes]
#
# Prints `status <s>` on every change. Exits 0 with `done <s>` once the
# status is final (success, failed, canceled, skipped, manual; none after three minutes), and
# 3 with `still <s>` after max-minutes (default 25, under the background
# command limit), which means: start it again. Exits 2 on a lookup error.

forge=$1 project=$2 mr=$3 poll=${4:-60} max=${5:-25}
[ -n "$forge" ] && [ -n "$project" ] && [ -n "$mr" ] || { echo "usage: wait-ci.sh <glab|gh> <project> <mr> [poll-seconds] [max-minutes]"; exit 2; }

status_of() {
  case "$forge" in
    glab)
      enc=$(printf '%s' "$project" | sed 's|/|%2F|g')
      # head_pipeline's own status comes before its nested detailed_status.
      glab api "projects/$enc/merge_requests/$mr" 2>/dev/null |
        grep -o '"head_pipeline":{[^{}]*"status":"[a-z_]*"' |
        sed 's/.*"status":"\([a-z_]*\)"/\1/'
      ;;
    gh)
      gh pr view "$mr" --repo "$project" --json statusCheckRollup --jq '
        .statusCheckRollup as $c
        | if ($c | length) == 0 then "none"
          elif any($c[]; (.conclusion // .state // "") | test("FAILURE|ERROR|TIMED_OUT|ACTION_REQUIRED")) then "failed"
          elif any($c[]; (.conclusion // .state // "") == "CANCELLED") then "canceled"
          elif any($c[]; (.status // "COMPLETED") != "COMPLETED" or .state == "PENDING" or .state == "EXPECTED") then "running"
          else "success" end' 2>/dev/null
      ;;
    *) echo "unknown forge: $forge"; exit 2 ;;
  esac
}

last="" start=$(date +%s)
while :; do
  s=$(status_of)
  [ -n "$s" ] || s=none
  if [ "$s" != "$last" ]; then echo "status $s"; last=$s; fi
  case "$s" in
    success|failed|canceled|skipped|manual) echo "done $s"; exit 0 ;;
    # Right after a push the pipeline may not exist yet; no CI at all shows
    # as none for good, and is final after a few minutes.
    none) [ $(( $(date +%s) - start )) -ge 180 ] && { echo "done none"; exit 0; } ;;
  esac
  if [ $(( $(date +%s) - start )) -ge $(( max * 60 )) ]; then echo "still $s"; exit 3; fi
  sleep "$poll"
done
