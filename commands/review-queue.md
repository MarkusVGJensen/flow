---
description: "List the merge requests awaiting your review, then start one"
argument-hint: "[mr-id]"
allowed-tools: ["Bash", "Read"]
---

# Review queue

Show what is waiting on the user, compactly, then let them pick one.

If `$ARGUMENTS` names an MR id, skip the listing and go straight to `/flow:review-mr <id>`.

## 1. Config

Read `.claude/flow.json` in the repo if present, else `~/.claude/flow.local.json`. You need `forge`
and `project`. If neither file exists, say so and stop — do not guess a project path.

## 2. Fetch in one call

```
ME=$(glab api user | python -c "import sys,json;print(json.load(sys.stdin)['username'])")
glab api "projects/<url-encoded project>/merge_requests?state=opened&reviewer_username=$ME&per_page=50"
```

Encode the project path (`group/repo` → `group%2Frepo`). For `forge: gh`, use
`gh pr list --search "review-requested:@me" --json number,title,author,isDraft,mergeable`.

## 3. Render

One line per MR, aligned, newest first. Show only what changes a decision:

```
!212  Fix overlapping labels on the settings page      alice
!208  Retry uploads after a dropped connection         bob     conflicts
!205  Cache parsed config between requests             bob     draft
```

- `draft` when `draft` is true — usually not worth reviewing yet, say so if the user picks one.
- `conflicts` when `has_conflicts` is true — the author has rebasing to do; a review is still useful
  but line anchors may move.
- Nothing else. No pipeline column, no dates, no URLs — they cost width and rarely change the choice.

Then: `pick one to review, or /flow:review-mr <id>`.

## 4. Hand off

When the user picks, run `/flow:review-mr <id>`. Do not start reviewing inline — the review needs its
own worktree and its own context.
