---
description: "Take an issue from a worktree to a merge request, stopping twice for approval"
argument-hint: "<issue-id> [extent]"
allowed-tools: ["Bash", "Glob", "Grep", "Read", "Write", "Edit", "Task"]
---

# Start an issue

Drive issue `$ARGUMENTS` from nothing to an open MR. There are exactly **two** stops: the plan, and
the pushed commits. Between them, do not ask permission for ordinary work.

## 0. The progress file

`<worktree>/.flow-state.json` records how far this issue has come, so a session that dies, is
compacted, or is resumed tomorrow picks up at the right step instead of starting over:

```json
{"issue": 128, "branch": "me/128-slug", "step": 6, "name": "tester", "status": "done", "at": "2026-09-14T10:12:00Z"}
```

- **Before step 2**, if the worktree for this issue already exists and holds this file, say in one line
  where you are resuming from and continue with the **next** step. Do not redo a step marked `done`.
  A gate marked `waiting` means the user has not approved yet: show them the plan or diff again and
  wait.
- **After every numbered step** below, rewrite the file with `status: done`. **At a gate**, write it
  with `status: waiting` before you stop, and `done` when the user approves.
- The first time you create it, keep it out of the diff:
  `echo .flow-state.json >> "$(git rev-parse --git-dir)/info/exclude"`.
- `/flow:status` and Helm's timeline read this file. Nothing else does.

## 1. Config and issue

Read config (`.claude/flow.json`, else `~/.claude/flow.local.json`). Fetch the issue:

```
glab api "projects/<enc>/issues/<id>"
```

Read the description **and the comments** — the thread usually narrows what is actually wanted.

## 2. Claim a worktree

Slug from the issue title: lowercase, non-alphanumerics to `-`, collapse repeats, trim to ~50 chars.
Branch from `branchPattern`. Worktree at `<worktreeRoot>/<issue>`.

```
git worktree add <worktreeRoot>/<issue> -b <branch> origin/<defaultTarget>
```

If the path exists and holds a progress file for **this** issue, resume (step 0). If it exists without
one, ask before touching it — another session may own it.

**Everything after this runs in that worktree.** Never build or edit in the directory you started in.

## 3. Route the extent

Invoke the `extent-router` skill. It picks single-agent, subagents, a team, or a workflow.

Below a team: proceed silently. At a team or workflow: show the choice, the agent count and a rough
token estimate, and **wait**.

## 4. Research, then architect — read-only

First the reading, on the cheap model. Fan out `flow:researcher` agents **in parallel**, one per area
the issue touches (the subsystem named in the issue, its tests, its callers, a comparable past change).
Each gets one question and returns a factual brief. Reading is most of the tokens in planning and needs
no judgement, which is why it runs on Sonnet while the thinking below does not.

Then task the `code-architect` agent (from `feature-dev`) with the issue **and the briefs**. It must
produce, and must not write code, the **plan document**, in this order and under these headings. The
architect has no Write tool, so it returns the document and you write it, unchanged, to
`<worktree>/.flow-plan.md`:

1. **Issue** — what is actually wrong or missing, in the reader's terms, with what the comments on the
   issue narrowed it to. Not a restatement of the title.
2. **Fix** — the shape of the solution in a paragraph, and the alternatives considered with a line each
   on why not.
3. **Design** — how the pieces fit, as UML in fenced `mermaid` blocks: a `classDiagram` of the classes
   touched and added with the members that change, and a `sequenceDiagram` for each flow whose order
   of calls matters. One diagram per concern; a diagram nobody needs is left out.
4. **Classes and files** — a table, one row per class or file: path, modified or added, what changes
   in it, and the signatures of anything new or changed.
5. **Tests** — the **test list**, one line per behaviour, named after the behaviour, and under each the
   file it goes in. The tester writes exactly these.
6. **Views** — only when the change has a visible part. One mockup per view or state, drawn as a fenced
   ASCII box or as an inline `<div>` with inline styles, showing the layout as it is meant to look;
   then a **colour table** — role, hex value in backticks (`#1d2c37`), where it is used — using the
   project's own tokens or palette where it has one, so the implementer and the reviewer judge the same
   intent.
7. **Done means** — the observable conditions under which the issue is closed, and the verification
   that proves each.

Keep it out of the diff the first time it is written:
`echo .flow-plan.md >> "$(git rev-parse --git-dir)/info/exclude"`. Helm shows the file under **Plan**,
diagrams drawn, so the terminal gets the one-line summary and the file gets the detail. When the plan
changes after the gate, rewrite the file: it is the record of what was agreed, and the implementer,
the tester and the reviewer read it.

## 5. ■ Gate 1 — the plan

Say in a few lines what the plan does and that the document is in `.flow-plan.md` (Helm: the **Plan**
button), then stop. Any clear yes is approval; Helm's **Approve plan** button types "The plan is
approved. Continue.", possibly followed by a note to take into account. Answer design questions. Re-run the architect if the shape changes, and have it
rewrite the file; do not patch a plan you no longer believe in.

## 6. Tester — red

Task the `flow:tester` agent with the approved test list from `.flow-plan.md`. Tests must fail for the right reason:
the behaviour is missing, not because they do not compile.

Build with `verify.targeted` — one test target. Never the whole project here.

## 7. Implementer — green

Task the `flow:implementer` agent with the plan document. It may not edit the tests. Between iterations use `verify.syntaxCheck`,
which costs seconds; reach for `verify.targeted` only when you need to actually run them.

Loop tester ↔ implementer until green. If it takes more than three rounds, stop and say why — the
plan is probably wrong.

## 8. Self-review — fresh context

Task the `flow:reviewer` agent on the full diff. It has not seen the implementation being written,
which is the point. Route real findings back to the implementer; ignore anything in `review.mute`.

## 9. Gate build

Run **every** command in `verify.gate`. A change that compiles on one build system and not the other
is not done. Fix and re-run until clean.

## 10. Format — last

Run `verify.format`, then `verify.scripts` and `verify.pbxproj` if they apply. This step rewrites file
mtimes and forces a full rebuild next time, which is why it is last and not continuous.

Then stamp it, or the commit gate will block the MR step:

```
touch "$(git rev-parse --git-dir)/flow-formatted"
```

## 11. ■ Gate 2 — the commits

The user reads the work one commit at a time, in Helm's **Review commits** page, so the branch has
to be worth reading that way before it stops here.

1. **Shape the series.** The working history is scaffolding — tester red, implementer green, review
   fixes, a formatting pass. Rewrite it (`git rebase -i` is not available; use `git reset --soft
   origin/<defaultTarget>` and recommit, or `git commit --fixup` plus `git rebase --autosquash`) into
   commits that each do one thing and build on their own, in the order the change is best understood:
   tests with the code they test, a rename apart from a behaviour change, and never a later commit
   that fixes an earlier one. Single-line messages, imperative, `{issue} - What this commit does`.
   A small change is one commit; do not split for the sake of splitting.
2. **Push the branch.** `git push -u origin <branch>`. If the branch is already on the remote from an
   earlier pass through this gate, tag a backup (`git tag backup/<branch>-<stamp>`) and push with
   `--force-with-lease`. Never a bare `--force`; the guard blocks it.
3. **Stop.** Write the progress file with `status: waiting`. Say in one line how many commits there
   are and that they are on the remote, and that the user can go through them under Review commits.
   Marks the user submits from that page arrive as one message: act on them, keep the series
   readable (fold a fix into the commit it belongs to), push again with `--force-with-lease` after a
   backup tag, and stop again. Do not open the merge request until the user approves; Helm's **Approve
   commits** button types "The commits are approved. Open the merge request."

Nothing else is squashed or opened here.

## 12. MR

On approval, task `flow:mr-creator`. It squashes, pushes with `--force-with-lease` (the branch is
already on the remote from step 11), opens the MR titled `{issue} - What was fixed` with the fixed
description layout, assigns the user and **no reviewers**, and returns the link. It does not edit
source.
