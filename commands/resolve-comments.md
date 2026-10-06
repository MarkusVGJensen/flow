---
description: "Act on the review comments left on your merge request"
argument-hint: "<mr-id>"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Edit", "Task"]
---

# Resolve review comments

Work through the comments on MR `$ARGUMENTS`.

## 1. Read them in context

```
glab api "projects/<enc>/merge_requests/<iid>/discussions"
```

For each unresolved discussion, read the comment **and the code it points at**. A comment you have not
located in the code is a comment you have not understood.

## 2. Sort them

- **Fix** — a real defect, or a convention the repo actually holds. Do it.
- **Discuss** — you disagree, or the reviewer misread something. Draft a reply for the user; do not
  argue on their behalf without showing them first.
- **Already right** — the code is correct and the comment is mistaken. Say why, briefly.

Never make a change you think is wrong just because a reviewer asked. Say so instead.

## 3. Fix

Route real fixes through the implementer, tests first where behaviour changes. Then `verify.gate` and
`verify.format`, then `touch "$(git rev-parse --git-dir)/flow-formatted"` so the commit gate passes.

## 4. One commit

Everything lands as a single commit named `Resolve comments`. Never amend the reviewed commits — the
reviewer needs to see what changed since they looked.

## 5. Report

Per comment: fixed, replied, or disputed, with a line each. Do not resolve the threads in GitLab —
that is the reviewer's call.
