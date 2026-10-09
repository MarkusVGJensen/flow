---
description: "Where this worktree stands in the flow: step, gate, branch, MR and pipeline"
argument-hint: ""
allowed-tools: ["Bash", "Read"]
---

# Status

Say where the work in the current directory stands, in six lines or fewer. Read only; no builds, no
fixes, no fetches that change anything.

1. **Progress.** Read `.flow-state.json` here. Report issue, step number and name, status and when.
   Missing file: say "no flow in progress in this worktree" and skip to 3.
2. **Next.** From the step and status, say what happens next and whether it needs the user:
   - `active` — the step is under way, or was interrupted if no session is running here: "working on
     step 7, implementer".
   - `done` or `skipped` — the next step is about to start; for `skipped`, name the step that was
     skipped.
   - `waiting` — at step 5, "waiting for you to approve the plan"; at step 11, "the commits, pushed
     and ready to read under Review commits".
   - `done` at step 12 — "MR open, nothing to do here".
3. **Branch.** `git status -sb` and the count from `git log --oneline origin/<defaultTarget>..HEAD`
   (config from `.claude/flow.json`, else `~/.claude/flow.local.json`). Mention uncommitted files if
   there are any.
4. **MR.** `glab mr view --output json` for the current branch (`gh pr view --json
   state,statusCheckRollup,reviewDecision` when `forge` is `gh`). If one exists: state, head pipeline
   status, number of unresolved discussions. If not: say so.

Format: one line per item, plain words, no headings. If something cannot be read, say which and move
on.
