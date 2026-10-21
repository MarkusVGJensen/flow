---
description: "Act on the review comments on your merge request: judge each, fix the valid ones in one commit on top, post replies, stopping twice for approval"
argument-hint: "<mr-id> [--reply-only] [note]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Edit", "Agent", "LSP"]
---

# Resolve review comments

Work through the open comments on MR `$ARGUMENTS`. Run this whenever the user asks whether comments
are resolved, to judge them, to fix them, or to reply to them. Helm's **Resolve comments** button
types this command into an issue's tab once its commits are approved and its MR is open.

- The first token is the MR id.
- `--reply-only`: judge and draft replies; change no code.
- Anything else is the user's **note**. It outranks this file. Example: "only the threading ones,
  and fix them without asking" limits the work to those comments and skips the first stop.

Config: `.claude/flow.json`, else `~/.claude/flow.local.json`.

Stop for the user exactly twice: at the verdicts (step 3) and at the replies (step 5).

## 1. Collect

```
glab api "projects/<enc>/merge_requests/<iid>/discussions?per_page=100"
glab api "projects/<enc>/merge_requests/<iid>/draft_notes"     # your own drafts, from a self-review
```

Take each unresolved discussion, and each of your own draft notes. Number them 1, 2, 3, … in the order of the diff (file, then line),
general comments last; the numbers are how the user, the commit and the replies refer to them.

For each, open the code it points at, in the MR's head. A comment you have not found in the code is a
comment you have not understood. Several comments over several files: hand the reading to
`flow:researcher` agents in parallel (`models.research`), one per group of files, as the
`extent-router` skill says.

## 2. Judge

Put each comment in one group, with a one-line reason:

| Verdict | When | Action |
| --- | --- | --- |
| **Fix** | A real defect, or a convention the repository actually follows. | Fix exactly what it asks. |
| **Discuss** | You disagree, or the reviewer misread the code. | Draft a reply. |
| **Already right** | The code is correct and the comment is mistaken. | Draft a short reply saying why. |

Never make a change you think is wrong because a reviewer asked; draft the reply instead. Read the
linked issue before judging a "this is unused" comment: groundwork for a later issue often looks
unused.

## 3. ■ Stop 1: the verdicts

Print one row per comment: number, author, `file:line`, the comment in a few words, verdict, reason,
and the planned fix or the gist of the reply. Then stop and wait.

- Any clear yes approves every verdict as shown.
- The user may change a verdict ("2 is right, leave it", "fix 4 too"): take it, show the changed
  rows, and go on without asking again.
- With `--reply-only`, or no **Fix** comment, skip step 4.

## 4. Fix, in one commit on top

Fix only the **Fix** comments, and in each only what the comment asks. Something else you would
change goes in the report.

- **Who:** task `flow:implementer` (`models.build`) with the comments, the files and the verify
  commands. A comment that changes behaviour goes to `flow:tester` first. Comments on separate files
  may go to several implementers in parallel; comments sharing a file go to one.
- **Check:** `verify.targeted` for what changed, through the lock script:
  `sh "${CLAUDE_PLUGIN_ROOT}/scripts/with-build-lock.sh" <command>`.
- **Format:** the changed files, then the stamp in the same command:
  `<formatter> --file <path> && touch "$(git rev-parse --git-dir)/flow-formatted"`.
- **Commit:** one commit on top of the branch, naming the comments it fixes by number:
  ```
  git commit -m "Resolved comments 1, 2, 3" -- <files>
  ```
  Never fold the fixes into the earlier commits: a rewrite moves the anchors of every open
  discussion, and the reviewer could no longer see what changed since their review.
- **Push:** a plain `git push`. No rewrite, so no force. If it is rejected, the remote moved: stop
  and report.

## 5. ■ Stop 2: the replies

Draft one reply per comment, in the user's voice: short, factual, no thanks or apologies.

- **Fix:** what changed, and the commit: "Fixed in abc1234: the lock is now taken before the read."
- **Discuss** and **Already right:** the reason, with the `file:line` that shows it.

Print them, numbered as before, and stop. Any clear yes posts them all; the user may edit or drop
single ones first ("drop 3", "say in 2 that …"). Post each as a reply in its own thread:

```
glab api -X POST "projects/<enc>/merge_requests/<iid>/discussions/<discussion-id>/notes" -f body=<reply>
```

- A comment that is one of your own draft notes gets no reply. Delete it only when the user asks,
  e.g. "fix them, then delete the comments".
- Never resolve a thread; that is the reviewer's call.

## 6. Report

One line per comment: fixed (in which commit), replied, or left. Then anything noticed but left
alone. The push started a pipeline; watch it as `/flow:watch-pipeline <mr>` describes.
