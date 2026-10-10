---
description: "Review someone else's merge request and post line-anchored draft comments"
argument-hint: "<mr-id> [--hold] [note]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Write", "Agent", "Skill"]
---

# Review a merge request

Review MR `$ARGUMENTS` and leave **draft** comments on it. Never submit the review — the user prunes
the drafts by hand and submits them.

The first token of `$ARGUMENTS` is the MR id. A `--hold` token anywhere after it means **hold**: write
the comments to the notes file and post nothing (steps 7 and 10 say what changes). Helm passes it, then
shows the comments on the diff, lets the user edit and prune them, and posts the survivors itself.
Anything else after the id is the user's **note**, and the note outranks this document: it may name the parts to focus on, lenses to skip, whether to build, or that a
worktree is not wanted. Read it before step 2 and let it shape steps 2, 4 and 5. With no note, follow
the defaults below.

## 1. Config and metadata

Read config (`.claude/flow.json`, else `~/.claude/flow.local.json`). Then:

```
glab api "projects/<enc>/merge_requests/<iid>"
```

Keep `source_branch`, `target_branch`, and all three of `diff_refs.base_sha`, `.head_sha`,
`.start_sha` — a line-anchored note is rejected without them.

If `draft` is true, say so in the report and carry on; the author knows the anchors may move.

## 2. Claim a worktree — unless you already have one, or the note says not to

If the current directory is already a checkout of the MR's head (Helm starts you in one at
`<worktreeRoot>/review-<iid>`), use it as is. If the note says no worktree, review from the diff alone
(`glab mr diff <iid>` and `glab api …/merge_requests/<iid>/changes`) and skip step 4 entirely.

Otherwise claim `<worktreeRoot>/review-<iid>`. If it exists, reuse it and `git fetch` — do not delete
a worktree another session may be using.

```
git worktree add <worktreeRoot>/review-<iid> --detach
cd <worktreeRoot>/review-<iid> && git fetch origin <source_branch> && git checkout FETCH_HEAD
```

## 3. Scope the review to the diff

```
git diff --name-only <base_sha>..<head_sha>
```

That file list *is* the review scope. Do not review the whole repository, and do not comment on code
the MR did not touch — a pre-existing problem is not this author's to fix.

## 4. Build only if a finding needs it

Most findings come from the diff and its neighbours. Build (with the commands in `verify.gate`)
only when you need to confirm a specific claim, and say in the report that you did.

## 5. Fan out — as wide as the diff deserves, no wider

Size first. A one-file fix gets `code-reviewer` alone. The table below is the ceiling for a large
diff, not the default, and the note wins over the table: "focus on the threading" means the lenses that
bear on threading and nothing else.

Launch the chosen `pr-review-toolkit` agents **in parallel**, one Agent call per lens, each given the
changed file list and told to review only those files, and with `models.lenses` from the config as
the model when it is set:

| Lens | When |
| --- | --- |
| `code-reviewer` | always |
| `silent-failure-hunter` | error handling, catch blocks, or early returns changed |
| `pr-test-analyzer` | test files changed, or behaviour changed without tests |
| `comment-analyzer` | comments or docs changed |
| `type-design-analyzer` | new or modified types |
| `security-review` skill | input parsing, auth, file paths, shell or SQL built from data, deserialization, secrets or network handling changed. A skill, not an agent: invoke it yourself, on the diff between `base_sha` and `head_sha`, alongside the agents |

## 6. Filter hard

Drop a finding if any of these hold:

- confidence below `review.floor`
- it matches anything in `review.mute`
- it restates another agent's finding — keep the best-argued one only
- it is a preference with no rule behind it in CLAUDE.md
- it is **pure hardening**: the only case it guards against is one no caller, input or state in the
  codebase can produce today. A null check on a value that is never null, a bounds check on an index
  the type already constrains, a guard against a message the protocol cannot send — none of these is
  a finding, however cheap the guard. It becomes a finding only when the case can actually arise, and
  then the comment names the caller or input that produces it, or when a rule in CLAUDE.md asks for
  the guard explicitly.

Aim for the comments a good reviewer would actually leave. Ten precise comments beat forty.

### Removal claims must be proven, not observed

A finding that says code is unnecessary — a dead rule, a redundant selector or condition, an
unreachable branch, a superfluous guard — is established only by exercising the case where it *would*
matter. Observing no change in the default case proves nothing: a guard exists for the non-default
case, which is exactly why it looks redundant from where you are standing.

Before such a finding survives the filter, construct the state that needs it and measure with and
without. A throwaway program, a scratch test, a one-off script — whatever makes the difference
observable. If you cannot construct that state, the finding is a **Question** asking the author what
case it covers, never an **Issue** telling them to delete it.

Treat this as the highest-cost mistake this command can make. A confident, well-argued instruction to
remove something load-bearing reads as the most valuable comment in the review, and it is the one most
likely to be acted on without checking.

## 7. Write the notes file first

Save survivors to `<worktree>/.flow-notes.json` **before** posting anything:

```json
{
  "mr": 123,
  "base_sha": "…", "start_sha": "…", "head_sha": "…",
  "summary": "The cover letter of step 8b.",
  "notes": [
    {"path":"src/A.cpp","start_line":38,"line":42,"side":"new","kind":"Issue","severity":4,"body":"**Issue:** …"}
  ]
}
```

- The three SHAs are the `diff_refs` from step 1: the line numbers belong to that diff.
- `line` is always the **last** line the comment is about. `start_line` is its first line; leave it out
  when the comment really is about one line. See step 8a for why.
- `side` is `"new"`, or `"old"` when the lines are removed ones and numbered on the old side.
- `body` is the comment exactly as GitLab should get it, opening with its `**Kind:**` (step 9).
- `severity` is for the user's eyes only and never goes into a body:

  | | |
  | --- | --- |
  | 5 | Must not merge as it is: a bug on a real path, data loss, a security hole, a broken build. |
  | 4 | A real defect or a missing test for changed behaviour, on a path that matters less. |
  | 3 | Worth changing in this MR: misleading code or comments, error handling that hides failures. |
  | 2 | Would make it better, fine to leave: a simpler shape, a clearer name. |
  | 1 | A nit. |

  Score the harm if the comment is ignored, not your confidence in it; confidence was step 6's filter.

Draft notes cannot be edited safely — the recovery path is delete-all then re-post from this file, so
it must exist first.

**With `--hold`, stop here.** Write the cover letter of step 8b into `summary` instead of posting it,
skip steps 8 to 8b entirely, and go to step 10. Do not post, delete or touch any draft note: the user
goes through the comments in Helm and Helm posts them.

## 8. Post as drafts

One POST per finding. `Content-Type` is required or GitLab answers 415:

```
glab api --method POST "projects/<enc>/merge_requests/<iid>/draft_notes" \
  -H "Content-Type: application/json" --input note.json
```

```json
{
  "note": "**Issue:** …",
  "position": {
    "position_type": "text",
    "base_sha": "…", "start_sha": "…", "head_sha": "…",
    "new_path": "src/A.cpp", "old_path": "src/A.cpp",
    "new_line": 42
  }
}
```

- Comment on a **deleted** line: `old_line` instead of `new_line`, and no `new_line`.
- A note with a `start_line` also gets a `line_range` (step 8a). The position's own `new_line` is
  still the range's **end** line.
- Never `PUT` an existing draft note — it unanchors it. Delete and re-post from `.flow-notes.json`.

## 8a. Anchor on the whole range, or on its last line

The MR's Overview tab shows a line comment under a snippet of the diff that **ends at the anchored
line**: a few lines above it, nothing below. Anchor a comment about lines 38-42 on line 38 and a
reader on the Overview sees the code *before* the block, not the block itself.

So:

- A comment about several lines — a loop, a function, a test, "this block" — is posted as a
  **multi-line range** covering all of them, so the Overview shows exactly those lines.
- If a range can't be posted (it spans hunks, or GitLab rejects it), anchor on the range's **last**
  line, never its first, so the lines above it show as context.
- Phrase the body to fit: "the loop above", not "the loop below".

A range is a `line_range` inside `position`, next to the single-line fields:

```json
"line_range": {
  "start": {"line_code": "<sha1(new_path)>_<old>_<new>", "type": "new", "new_line": 38},
  "end":   {"line_code": "<sha1(new_path)>_<old>_<new>", "type": "new", "new_line": 42}
}
```

- `line_code` is the SHA-1 hex of the file path, then the line's old-side and new-side numbers at
  that point in the diff. On an added line the old number is the old-side counter at that spot, the
  number the next unchanged line would have. Work both numbers out from the hunk; don't guess them.
- `type` is `"new"` for an added line, `"old"` for a removed one (then `old_line` in place of
  `new_line`), and left out for an unchanged context line.
- Both ends must be in the same hunk.
- After posting, `GET` the draft and check that `position.line_range` survived. If it didn't, delete
  that draft and re-post it on the end line alone.

## 8b. One summary note

After the anchored drafts, post **one** more draft note with no `position`: the cover letter. One
paragraph, in this order: what was reviewed (files and roughly how many lines), which lenses ran and
which were skipped and why, whether anything was built, how many Issues, Questions and Suggestions
follow, and the user's note if there was one. A reader who opens the MR a week later should
understand what this review did and did not look at. It is a draft like the others, so the user can
delete it before submitting.

## 9. Comment form

Open every comment with `**Question:**`, `**Issue:**` or `**Suggestion:**`. Then the problem in one or
two sentences, and a concrete fix. No preamble, no praise, no restating the code.

If something looks over-complex, say what the simpler shape would be and what it would cost — the
author may have a reason you cannot see from the diff.

## 10. Report

Print what you posted, grouped by severity, with a one-line total. Remind the user the notes are
drafts: they prune in GitLab and submit there. Never submit for them.

With `--hold`, print the same grouping of what is in `.flow-notes.json` and say that nothing has been
posted: the comments wait in Helm's **Review comments** page, where the user edits them and posts them
as drafts. If asked later to change or add comments, edit `.flow-notes.json` — it may already have
been pruned by the user, so read it first and keep what is there.
