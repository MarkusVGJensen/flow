---
description: "Watch a pipeline until green, fixing real failures and retrying flaky ones"
argument-hint: "[mr-id]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Edit", "Agent"]
---

# Watch the pipeline

Watch the pipeline for `$ARGUMENTS` (default: the MR for the current branch) until it is green or you
stop. This is the only part of `flow` that writes to shared infrastructure
without asking each time, so the limits below are absolute.

It starts in four ways: typed, or from Helm's **Watch pipeline** button; at the end of
`/flow:start-issue`, once the MR is open; and after any push of a branch with an open MR, when the
`watch-after-push` hook tells you so. Already waiting on that MR: keep the one waiter.

## Refuse outright

Stop immediately, with a one-line reason, if any of these hold:

1. **The branch is not the user's own.** Never a branch they are reviewing. Never the default branch.
2. **Attempts are spent** — `ci.attempts` for a normal job, `ci.attemptsBlind` for one matching
   `ci.blindJobPattern`.

## Wait without spending tokens

Do not poll by hand: every check would be a model turn. The plugin ships a waiter that polls on its
own and only returns when CI has finished:

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci.sh" <forge> <project> <mr> <ci.pollMinutes × 60> 25
```

The arguments come straight from the config: `forge` is `glab` or `gh` exactly as written there,
`project` is the config's `project`. Example with `pollMinutes: 10`:

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci.sh" glab tmsdk/safepilot 4432 600 25
```

Start it with the Bash tool's `run_in_background: true` and end your turn with one line saying what you are
waiting for. **Several MRs** (a stack, or the user names more than one): one waiter per MR, each its
own background call, never several joined with `&` in one command. Handle each as it finishes. It prints `status <s>` on each change and exits:

- `done success` — green. Report and stop.
- `done failed` (or `canceled`) — triage, below.
- `done none` — no pipeline ran for this MR. Say so and stop.
- `still <s>`, exit 3 — 25 minutes passed, which is under the background limit. Start it again; it
  is not an attempt.

When you are woken by its exit, read its output and carry on. If you are not woken (an environment
without background notifications), check it with the Bash tool when the user next speaks.

## Triage each failed job

Fetch the trace before deciding anything:

```
glab ci trace <job-id>          # or: glab api "projects/<enc>/jobs/<id>/trace"
```

| Failure | Action |
| --- | --- |
| Test in `ci.flakyTests` | Retry that job. Once. Do not "fix" a known flake. |
| Job ran past `ci.stalledJobMinutes` with no output | Restart it. A stall, not a result. |
| Real failure | Fix it (below). |
| Anything you cannot attribute to a specific cause | **Stop and report the trace excerpt.** Do not guess. |

## Fixing a real failure

1. Read the trace and find the actual error — not the first red line, the cause.
2. Fix it in the worktree. Verify locally with `verify.targeted` **if the platform allows**. A job
   matching `ci.blindJobPattern` cannot be verified locally; say so explicitly in every report.
   Fix only the failure. Nothing the trace does not point at, even if it looks like an improvement.
3. Format the files you changed, with the stamp in the same command:
   `<formatter> --file <path> && touch "$(git rev-parse --git-dir)/flow-formatted"`. Never touch the
   stamp on its own.
4. **Without open discussions on the MR, or when the user asked to fold:** fold the fix into the
   commit that introduced the fault (`git commit --fixup=<that commit>`, then
   `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<target>`), so the series reads commit by
   commit, not as a trail of CI fixes. Build the tip again before pushing.

   **With open discussions** (`glab api "projects/<enc>/merge_requests/<iid>/discussions"`) and no
   request to fold: a rewrite moves their anchors, so add the fix as a new commit
   (`{issue} - Fix <job>`), push it with a plain `git push`, and skip steps 5 and 6.
5. **Tag first:** `git tag backup/<branch>-$(date +%Y%m%d-%H%M%S)`
6. Push: `git push --force-with-lease`

`--force-with-lease`, never `--force`. If the lease fails, the remote moved — someone else pushed, or
another worktree did. **Stop and report.** Do not re-fetch and retry; that is how you overwrite work.

The push retriggers the pipeline. Count the attempt and start the waiter again.

## Report each cycle

One line: job, verdict, action taken, attempts remaining. On stopping, say which of the limits above
ended it, and what the user needs to look at.

## Never

- `git push --force` without lease
- Rewriting a commit that is not yours
- Retrying a job more than its limit "because it looked flaky"
- Fixing a failing test by changing what it asserts
