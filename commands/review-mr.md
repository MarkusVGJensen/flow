---
description: "Review a merge request and post line-anchored draft comments"
argument-hint: "<mr-id> [--hold] [note]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Write", "Agent", "Skill", "LSP"]
---

# Review a merge request

Review MR `$ARGUMENTS` and add your comments to it as **inline draft comments** in GitLab: each on its
file and its line, or on its range of lines when it is about several. Never anything else:

- No summary comment and no general comment on the MR, ever.
- Never submit the review. The user prunes the drafts and submits them.

Arguments:

- The first token is the MR id.
- `--hold`: write the comments to the notes file as they come and post nothing. Helm shows them on
  the diff as they land; the user edits them, adds their own, and submits the review from Helm. Helm
  always starts reviews this way.
- Anything else is the user's **note**, and it outranks this file. Example: "focus on the threading,
  no build" narrows steps 4 and 5. "no worktree" skips step 2. Read it before step 2.

## 1. Config and metadata

Read config (`.claude/flow.json`, else `~/.claude/flow.local.json`). Then:

```
glab api "projects/<enc>/merge_requests/<iid>"
```

Keep `source_branch`, `target_branch`, and all three of `diff_refs.base_sha`, `.head_sha`,
`.start_sha` — a line-anchored note is rejected without them.

If `draft` is true, say so in the report and carry on; the author knows the anchors may move.

Read the issue the MR closes (the `Closes #` line, or the issue number in its title or branch) and
the issues it links. They say what the MR is for, and what later issues will build on it: code that
looks unused may be groundwork for one of them.

**The user's own MR** (`author.username` is the user's): review it the same way. At the end, offer
`/flow:resolve-comments <iid>` to fix the drafts.

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

The lenses read the diff; you do not read it all first. You read what they report and check each
finding against the code.

- **One file, a few lines:** review it yourself.
- **Anything larger:** at least the `code-reviewer` agent, plus each lens from the table whose
  condition holds. Examples: 3 files of UI code with new types → `code-reviewer` and
  `type-design-analyzer`. 20 files with new error paths and tests → `code-reviewer`,
  `silent-failure-hunter` and `pr-test-analyzer`.
- **The note narrows the lenses:** "focus on the threading" means `code-reviewer` told to look at
  threading only.

Launch the chosen `pr-review-toolkit` agents **in parallel**, all in one message, one Agent call per
lens. Give each the changed file list, the base and head SHAs, the issue's purpose in a line, and the
instruction to review only those files. Pass `models.lenses` as the model when it is set. Use only the
lenses below; a focus the table lacks (simplicity, naming) goes to `code-reviewer` as an extra
instruction. Never use an agent that can edit files, such as `code-simplifier`, as a lens.

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

## 7. Write the notes file

Every comment sits on the lines it is about: a file, and either one line or a range of lines. There
is no summary comment and no general comment on the MR, in any mode. The overview of the review goes
in your report to the user (step 10), never to GitLab.

Write the surviving findings to the notes file before anything is posted. Keep both notes files out
of `git status`: list `.flow-notes.json` and `.flow-notes.posted.json` in
`"$(git rev-parse --git-path info/exclude)"`, appending only the lines it lacks.

- Without `--hold`: `<worktree>/.flow-notes.posted.json`, the record of what you posted.
- With `--hold`: `<worktree>/.flow-notes.json`, which Helm shows and posts. Never use this name for
  comments you post yourself, or Helm offers to post them a second time.

```json
{
  "mr": 123,
  "base_sha": "…", "start_sha": "…", "head_sha": "…",
  "notes": [
    {"path": "src/A.cpp", "start_line": 38, "line": 42, "side": "new", "kind": "Issue", "severity": 4,
     "body": "**Issue:** The loop above re-reads the file on every pass. Read it once before the loop."},
    {"path": "src/B.h", "line": 17, "side": "new", "kind": "Question", "severity": 2,
     "body": "**Question:** Can this be null when the store is offline?"}
  ]
}
```

- **SHAs:** the three `diff_refs` from step 1. The line numbers belong to that diff.
- **`path`:** the file's path in the MR (its new path when renamed).
- **`line`:** the comment's **last** line. **`start_line`:** its first line, when the comment is
  about several lines: a block, a loop, a function, a test. Leave it out for a one-line comment.
  GitLab's Overview shows a comment under the code that ends at its last line, so a range shows
  exactly the lines meant, and a comment on one line shows the lines above it. Phrase bodies to fit:
  "the loop above".
- **`side`:** `"new"` for added or unchanged lines, numbered as in the new file. `"old"` for removed
  lines, numbered as in the old file.
- **`body`:** the comment exactly as GitLab gets it, opening with its kind (step 9).
- **`severity`:** for the user only, never in a body. Score the harm if the comment is ignored:

  | Severity | Meaning |
  | --- | --- |
  | 5 | Must not merge as it is: a bug on a real path, data loss, a security hole, a broken build. |
  | 4 | A real defect or a missing test for changed behaviour, on a path that matters less. |
  | 3 | Worth changing in this MR: misleading code or comments, error handling that hides failures. |
  | 2 | Would make it better, fine to leave: a simpler shape, a clearer name. |
  | 1 | A nit. |

**With `--hold`, write as you go and post nothing.** Helm shows the file live on the review tab's
Review commits page, where the user reads the comments on the code, edits or deletes them, adds
their own, and submits the review to GitLab. So:

- Write the file as soon as the first comment survives the filter, and rewrite it each time another
  does, instead of once at the end.
- Read the file before every rewrite. The user may have edited, deleted or added comments since.
  Keep their changes: never bring back a comment that is gone, and never change one they wrote.
- Touch no draft note on GitLab. Then go to step 10.

## 8. Post as inline drafts

Post with the plugin's script; never build GitLab positions by hand:

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/post-review.mjs" <project> <worktree>/.flow-notes.posted.json
```

For each note it posts one **draft** note on its file and lines: a range from `start_line` to `line`
when the note has one, otherwise the single line. It reads the diff of the exact MR version the notes
were written against, works out GitLab's line codes, checks that each range survived, and re-posts a
range GitLab refuses on its last line. It never posts a note without a position. Add `--dry-run`
first when unsure: it prints each anchor and posts nothing.

Read its output. One line per note:

- `ok path:38-42 (range)`: posted on all its lines.
- `ok path:42`: posted on one line.
- `ok … (on its last line: …)`: the range could not be kept. Say so in the report.
- `FAILED path:line: <error>`: not posted. Fix the note (usually a line not in the diff), write a
  file with only the failed notes, and run the script on that file.
- `warning: … has moved since this review`: the MR's head changed after your review. Say so in the
  report.

Never `PUT` a draft note: an edit unanchors it. To change a comment, delete that draft
(`glab api --method DELETE "projects/<enc>/merge_requests/<iid>/draft_notes/<id>"`), update the notes
file, and post the changed note again.

## 9. Comment form

Open every comment with `**Question:**`, `**Issue:**` or `**Suggestion:**`. Then the problem in one or
two sentences, and a concrete fix. No preamble, no praise, no restating the code.

If something looks over-complex, say what the simpler shape would be and what it would cost — the
author may have a reason you cannot see from the diff.

## 10. Report

Start with one paragraph on what the review covered, in this order: what was reviewed (files and
roughly how many lines), which lenses ran and which were skipped and why, whether anything was built,
and the user's note if there was one. It goes in this report only, never on the MR.

Then print what you posted, grouped by severity, each as `path:line` or `path:start-end`, with a
one-line total and any note the script could not post or placed on its last line only. Remind the
user the comments are drafts: they prune them in GitLab and submit there. Never submit for them.
If asked later to change or add comments, delete the affected drafts, update
`.flow-notes.posted.json`, and post the changed notes with the script (step 8).

With `--hold`, print the same grouping of what is in `.flow-notes.json` and say that nothing has been
posted: the comments are on Helm's **Review commits** page, where **Submit review** publishes them.
If asked later to change or add comments, edit `.flow-notes.json`. Read it first: the user may have
pruned or added to it, and their changes stay.
