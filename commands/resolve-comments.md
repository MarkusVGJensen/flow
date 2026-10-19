---
description: "Act on the review comments on your merge request: judge each, fix the valid ones folded into their commits, draft replies"
argument-hint: "<mr-id> [--reply-only] [note]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Edit", "Agent", "LSP"]
---

# Resolve review comments

Work through the comments on MR `$ARGUMENTS`. Run this whenever the user asks whether comments are
resolved, to judge them, to fix them, or to reply to them.

- The first token is the MR id.
- `--reply-only`: judge and draft replies; change no code.
- Anything else is the user's **note**. It outranks this file. Example: "only the threading ones,
  and fix them without asking" limits the work to those comments and skips step 3's wait.

Config: `.claude/flow.json`, else `~/.claude/flow.local.json`.

## 1. Collect

```
glab api "projects/<enc>/merge_requests/<iid>/discussions?per_page=100"
glab api "projects/<enc>/merge_requests/<iid>/draft_notes"     # your own drafts, from a self-review
```

Take each unresolved discussion, and each of your own draft notes. For each, open the code it points
at, in the MR's head. A comment you have not found in the code is a comment you have not understood.

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

## 3. Show, then act

Print the table: comment (author, `file:line`, a few words), verdict, reason, planned fix or draft
reply. With `--reply-only`, or when any comment is **Discuss**, stop here and wait. Otherwise go on.

## 4. Fix, folded into the commits

Fix only the **Fix** comments, and in each only what the comment asks. Something else you would
change goes in the report.

- **Who:** task `flow:implementer` with the comments, the files and the verify commands
  (`models.build`). A comment that changes behaviour goes to `flow:tester` first. Comments on separate
  files may go to several implementers in parallel; comments sharing a file go to one.
- **Check:** `verify.targeted` for what changed, through the lock script.
- **Format:** the changed files, then the stamp in the same command:
  `<formatter> --file <path> && touch "$(git rev-parse --git-dir)/flow-formatted"`.
- **Fold:** each fix goes into the commit that introduced the code it fixes:
  ```
  git commit --fixup=<that commit> -- <files>
  GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<target_branch>
  ```
  The series stays readable commit by commit, with no "address review" commit on top.
- **Push:** `git tag backup/<branch>-$(date +%Y%m%d-%H%M%S)`, then `git push --force-with-lease`.
  If the lease fails, the remote moved: stop and report.

## 5. Replies and drafts

- Post nothing as the user. Print the drafted replies; post one only when the user says so, as a
  reply in its thread.
- Never resolve a thread; that is the reviewer's call.
- Your own draft notes: delete them only when the user asks, e.g. "fix them, then delete the
  comments".

## 6. Report

One line per comment: fixed (in which commit), replied, or disputed. Then anything noticed but left
alone.
