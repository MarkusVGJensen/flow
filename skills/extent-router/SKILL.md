---
name: extent-router
description: Choose how much machinery a task deserves — one session, subagents, an agent team, or a dynamic workflow. Use at the start of any task that reads or changes more than a few files, repeats one check over many places ("all the views", "every store"), hunts a regression, fixes several review comments, or might need parallel agents; and when sizing an issue.
---

# Choosing the extent

Choose by what the work is, not by habit. Defaulting to one session is the most common mistake: it
fills your context with files you read once, and long tasks then run out of context and get compacted
mid-work.

## The four extents

| Extent | Use when | Costs |
| --- | --- | --- |
| **One session** | You already know the one to three files involved, and the change is small. | 1× |
| **Subagents** | Reading you will not need again, independent pieces of one job, or a fresh pair of eyes. Only conclusions come back to you. | ~1–2× |
| **Agent team** | Long strands that run in parallel and must agree with each other as they go. | ~1× per teammate |
| **Workflow** | More agents than one conversation can steer, or orchestration worth rerunning. | dozens of agents |

## Examples

**One session**
- "Rename this parameter in `RouteStore.cpp`." You know the file; just do it.
- "Why does this test fail?" with the trace pointing at one function.

**Subagents**, the usual answer for anything bigger:
- "Seventeen views are still white in dark mode." One `flow:researcher` per group of views, in
  parallel, each returning which colours are hard-coded and where. You fix with the briefs in hand.
- "The font regressed somewhere since 2.3." Researchers in parallel: one reads the font setup, one
  the theme files, one `git log -p` over the range for font changes. Do not grep the tree yourself
  for an hour.
- "Fix these six review comments." When they touch different files, one implementer per group; when
  they touch the same files, one implementer for all of them, in order.
- "Review this 20-file MR." Review lenses in parallel (`/flow:review-mr` does this).
- The issue chain: researchers, then architect, tester, implementer, reviewer.

**Agent team**
- One feature built on Windows (Qt) and iOS (Swift) over a shared C++ model, where both sides must
  agree on the model's interface as it changes. One teammate per platform, plus one for the model.
- A deep investigation where three hypotheses are chased at once, and each finding changes what the
  others look at.

**Workflow**
- Change a call pattern in 300 files: one agent per batch of files, then a verifier per batch.
- A hard design question drafted three ways by independent agents, then compared by a judge.
- A sweep of every store class for the same defect, with each hit verified.

## Signals

- Toward **subagents**: more than three files to read; "find", "check every", "all the", "why does …
  regress"; a list of items that do not depend on each other; you notice yourself re-reading files.
- Toward a **team**: strands that run for an hour and depend on each other's results.
- Toward a **workflow**: "everywhere", "every file", a count in the hundreds, "answer this several ways
  and compare".

## Rules for parallel agents

- **Edits in parallel only on disjoint files.** Two agents editing in one worktree must never touch
  the same file. Builds go through the build lock (`with-build-lock.sh`).
- **One message, many Agent calls.** Agents in the same message run at the same time.
- **Each agent gets one question and the paths it needs.** It sees nothing of your conversation.
- **Ask for short answers:** a brief under 400 words, findings as `path:line`.

## The gate

- **One session or subagents:** proceed without comment.
- **Team or workflow:** stop. Say what you would run, how many agents, the rough token cost, and what
  the cheaper extent would miss. Wait for a yes.

## Correcting course

- Too small: you re-read files, lose track, or your context is half spent before the change starts.
  Hand the remaining reading to subagents.
- Too big: agents wait on each other more than they work, or five agents produce one small commit.
  Collapse to fewer.
