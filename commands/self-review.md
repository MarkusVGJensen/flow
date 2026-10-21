---
description: "Have a fresh-context agent review your branch where you point it, say which findings you would apply, and fold the approved ones into the existing commits"
argument-hint: "[focus]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Edit", "Agent", "LSP"]
---

# Self-review

Review this worktree's branch for its author, looking at what `$ARGUMENTS` names. Helm's **Review**
button types this command into an issue's tab with the focus the user typed; it can be typed by hand
too.

- Everything after the command is the **focus**, e.g. "optimizations and simplicity". It outranks
  this file. Empty: review for correctness and simplicity.
- This is the author's own review, nothing else. It never reads or writes review comments, never
  calls `glab` or `gh`, and has nothing to do with `/flow:resolve-comments`.
- It does not move `.flow-state.json`: a self-review is not a step of the chain.

Config: `.claude/flow.json`, else `~/.claude/flow.local.json`.

Stop for the user exactly once: at your verdict (step 3).

## 1. Review, in fresh context

Base: `origin/<defaultTarget>`, fetched first. The range is `<base>...HEAD`, plus uncommitted changes
when there are any. Nothing in the range: say so in one line and stop.

Task `flow:focus-reviewer` (`models.review`) with the range, whether uncommitted changes count, the
focus as given, and `<worktree>/.flow-plan.md` when it exists. Give it nothing of your own reasoning
about the code: its value is that it has none.

## 2. Show the findings

Print the agent's findings exactly as it returned them, numbers and confidences unchanged:

```
1 (92%): src/flow.ts:118 — withAgentStep re-parses the state on every redraw; parse once in the poller.
2 (85%): src/main.ts:729 — fillCommand tests openMr in two places; one early return covers both.
```

## 3. ■ Stop: your verdict

You wrote this code and know why it is the way it is; the reviewer does not. Judge each finding
against the code, not against your memory of it: open the lines first. Then say, in this shape:

```
I would apply 1, 2 and 5, folding each into the commit that introduced the code.
3: skip — renderTimeline is also called from the poller, so the parse cannot move there.
4: skip — changes the order buttons appear in, which the focus did not ask for.
```

Every finding you would skip gets a reason. A finding you cannot judge without trying it: say so and
count it as applied. Then stop and wait.

- Any clear yes applies your list as shown.
- The user may change it ("apply 3 too", "drop 5", "only 1"): take it and go on without asking again.
- No findings, or the user applies none: stop there.

## 4. Apply

Change only what each applied finding says. Something else you would change goes in the report.

- **Who:** small, local changes you make yourself. Several files or anything larger goes to
  `flow:implementer` (`models.build`) with the findings, the files and the verify commands; a finding
  that changes behaviour goes to `flow:tester` first. Findings on separate files may run in parallel;
  findings sharing a file go to one agent.
- **Check:** `verify.targeted` for what changed, through the lock script:
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/with-build-lock.sh" <command>`.
- **Format:** the changed files, with the stamp in the same command:
  `<formatter> --file <path> && touch "$(git rev-parse --git-dir)/flow-formatted"`. Never the stamp
  on its own; with no `verify.format`, touch the stamp alone.

## 5. Fold into the existing commits

Always fold; a self-review never adds a commit of its own.

1. For each changed hunk, find the commit in the range that last touched those lines:
   `git log --format=%h -s <base>..HEAD -L<start>,<end>:<file>`, newest first. Lines no commit in the
   range touched belong to the commit that changed that file most; a file no commit touched goes to
   the commit its change serves.
2. One `git commit --fixup=<sha> -- <files>` per target commit. Hunks of one file for two commits:
   stage them apart with `git apply --cached` on a patch of just those hunks.
3. `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`. A conflict: `git rebase --abort`, then
   stop and report which finding and which commit; never resolve it by dropping a change.
4. **Build the tip** with `verify.targeted` through the lock script. Do not build each commit.
5. **Push only when the branch is on the remote:** `git tag backup/<branch>-<stamp>`, then
   `git push --force-with-lease`. Never a bare `--force`. A failed lease means the remote moved:
   stop and report. A branch only on this machine stays unpushed.

## 6. Report

One line per finding: applied (into which commit) or skipped. Then whether the branch was pushed and
the backup tag. When the commits gate was already passed, add that the series changed and can be read
again under Helm's **Review commits**.
