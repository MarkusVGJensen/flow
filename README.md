# flow

An issue-to-MR workflow for Claude Code. A worktree per issue, a chain of agents with exactly two
human stops, forge-agnostic merge-request review that leaves line-anchored **draft** comments, and a
CI watcher with hard limits on what it may do unattended.

Built for a large C++ monorepo with two build systems, but nothing here is C++-specific: the project's
own conventions come from its `CLAUDE.md`, and everything machine-specific comes from one config file.

## Install

Either clone it where Claude Code picks up plugins:

```
git clone https://github.com/MarkusVGJensen/flow ~/.claude/skills/flow
```

or add it as a marketplace plugin:

```
/plugin marketplace add MarkusVGJensen/flow
/plugin install flow
```

Then copy `flow.config.example.json` to `~/.claude/flow.local.json` (personal) or `.claude/flow.json`
(shared with the repo) and fill it in.

For a desktop front end — a tab per issue, the review queue, one-click worktrees — see
[Helm](https://github.com/MarkusVGJensen/helm), which types these commands into embedded sessions.

## What you get

| Command | |
| --- | --- |
| `/flow:start-issue <id>` | Worktree, plan, red tests, implementation, self-review, gate build, format, pushed commits, MR |
| `/flow:review-queue` | The MRs waiting on you |
| `/flow:review-mr <id> [--hold]` | Fans out review lenses, filters hard, posts draft comments; `--hold` leaves them in `.flow-notes.json` with a severity each, for Helm to show on the diff and post |
| `/flow:resolve-comments <id>` | Acts on feedback, lands one commit |
| `/flow:watch-pipeline [id]` | Polls CI, fixes real failures, retries known flakes |
| `/flow:vs <file>[:line]` | Opens the file in Visual Studio |
| `/flow:status` | Where this worktree stands: step, gate, branch, MR, pipeline |

`/flow:start-issue` keeps a progress file, `.flow-state.json`, in the worktree and resumes from it, so a
session that dies or is compacted mid-chain continues at the right step. Its architect writes the plan
as a document, `.flow-plan.md`, beside it: the issue, the fix, the design as Mermaid UML, the classes
and files, the test list, mockups and a colour table when there is a UI, and what done means. Helm
renders it under **Plan**; in a plain terminal it is a Markdown file. `/flow:review-mr` ends with one
unanchored summary note, the review's cover letter.

Hooks, all on Bash: the **format gate** blocks a commit when source files changed after the formatter
last ran; the **bash guard** blocks `git push --force` without a lease and a tree-wide formatter run
that has not been acknowledged with `FLOW_TREEWIDE_OK=1`.

Agents: `tester` (writes red tests, never production code), `reviewer` (fresh-context diff review),
`mr-creator` (git only), `comment-resolver`. Skill: `extent-router`, for sizing a task.

## Companion plugins

`flow` delegates rather than reimplements. Install these from `claude-plugins-official`:

- **pr-review-toolkit** — the six review lenses `/flow:review-mr` fans out to
- **feature-dev** — `code-architect` and `code-explorer`, used for the planning step
- **code-simplifier**, **code-review** — quality passes
- **hookify**, **claude-md-management** — for maintaining your own setup
- a language server plugin for your language (**clangd-lsp**, **pyright-lsp**, …). This is the single
  biggest token saving available: symbol resolution instead of repeated grep sweeps.

## Adapting it

**The two gates are the design.** You approve a plan, then you approve the commits. Everything
between is uninterrupted. At the second gate the branch has been shaped into commits that read one
at a time and pushed, so you go through them in Helm's Review commits page (or any commit viewer)
before the MR exists; the MR step then squashes. If you remove a gate, remove the first — not the
second.

**Reviews report what can happen, not what could be guarded against.** A finding that only
protects a case no caller or input produces today is pure hardening and is dropped, in your own
self-review and in reviews of other people's MRs alike. Ask for the guard in `CLAUDE.md` if you
want it.

**Formatting runs once, at the end.** Continuous formatting rewrites file mtimes, which on a large
project forces a full rebuild every time. `verify.format` is deliberately the last step.

**The inner loop must stay cheap.** `verify.syntaxCheck` runs per edit and should cost seconds;
`verify.targeted` builds one test target. Full builds belong in `verify.gate` and nowhere else.

**Review findings are filtered, hard.** Raise `review.floor` and add to `review.mute` when a lens
reports something your team has settled. That is configuration, not a fork.

**The CI watcher's limits are not suggestions.** It force-pushes with lease, tags before every
rewrite, refuses to rewrite an MR that has open review comments, and stops after a fixed number of
attempts. If you loosen those, you will eventually lose someone's review.

## Using it for another language

Nothing in `flow` names a language. The `tester` agent takes its framework and test conventions from
your `CLAUDE.md`, and `verify.*` takes its commands from config. Point them at your project and it
works; write your test conventions down in `CLAUDE.md` and it works well.
