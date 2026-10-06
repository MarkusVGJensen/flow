---
description: "Watch a pipeline until green, fixing real failures and retrying flaky ones"
argument-hint: "[mr-id]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Edit", "Task"]
---

# Watch the pipeline

Poll the pipeline for `$ARGUMENTS` (default: the MR for the current branch) every `ci.pollMinutes`
until it is green or you stop. This is the only part of `flow` that writes to shared infrastructure
without asking each time, so the limits below are absolute.

## Refuse outright

Stop immediately, with a one-line reason, if any of these hold:

1. **The branch is not the user's own.** Never a branch they are reviewing. Never the default branch.
2. **The MR has open discussions or unresolved notes.**
   ```
   glab api "projects/<enc>/merge_requests/<iid>/discussions"
   ```
   A history rewrite unanchors line-anchored comments. Someone else's review is not yours to destroy.
   Report the failure and let the user decide.
3. **Attempts are spent** — `ci.attempts` for a normal job, `ci.attemptsBlind` for one matching
   `ci.blindJobPattern`.

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
3. Amend into the commit that introduced the fault — normally the single squashed commit — so the
   branch stays one readable change and not a trail of CI fixes.
4. **Tag first:** `git tag backup/<branch>-$(date +%Y%m%d-%H%M%S)`
5. Push: `git push --force-with-lease`

`--force-with-lease`, never `--force`. If the lease fails, the remote moved — someone else pushed, or
another worktree did. **Stop and report.** Do not re-fetch and retry; that is how you overwrite work.

The push retriggers the pipeline. Count the attempt and go back to polling.

## Report each cycle

One line: job, verdict, action taken, attempts remaining. On stopping, say which of the limits above
ended it, and what the user needs to look at.

## Never

- `git push --force` without lease
- Rewriting a commit that is not yours
- Retrying a job more than its limit "because it looked flaky"
- Fixing a failing test by changing what it asserts
