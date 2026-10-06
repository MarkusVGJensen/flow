---
name: extent-router
description: Choose how much machinery a task deserves — one session, subagents, an agent team, or a dynamic workflow. Use when sizing an issue or when a task feels like it might need parallel agents.
---

# Choosing the extent

Pick the smallest arrangement that can do the job. Each step up multiplies token cost, and the cost is
paid whether or not it helped.

## The ladder

**One session** — the default. A bug fix, a small feature, anything where the whole task fits in one
head. Most work is here. Do not talk yourself out of it.

**Subagents** — when the work has phases with different jobs (plan, then test, then implement), or
when a search would flood your context with files you will not keep. The phase boundary is the point:
what the subagent read never enters your context, only its conclusion. This is the workhorse of the
issue flow.

**An agent team** — when several long-running strands genuinely proceed in parallel and need to see
each other's results. Real cost: every teammate has its own context window, so a four-teammate team
costs roughly four sessions. Worth it for research, review, and new feature work; wasteful for
anything routine.

**A dynamic workflow** — when the task needs more agents than one conversation can coordinate, or when
the orchestration itself is worth keeping and rerunning. A codebase-wide sweep, a several-hundred-file
migration, a hard plan drafted from independent angles. Dozens to hundreds of agents.

## Deciding

Ask what the work actually is:

- One coherent change, one file or a few → **one session**
- Distinct phases, or a search whose output you do not want to keep → **subagents**
- Independent strands that must compare notes, running long → **team**
- A mechanical change across a large surface, or several independent attempts at one hard question →
  **workflow**

Signals for the top of the ladder: "everywhere", "all of", "every file", "rewrite X to Y", a count in
the hundreds, or a question worth answering three ways and comparing.

## The gate

**Subagents and below: just proceed.** Do not narrate the choice.

**A team or a workflow: stop.** Say what you would run, how many agents, roughly what it costs, and
what the cheaper option would miss. Then wait. Nobody wants to discover forty agents after the fact.

## Getting it wrong

Too small shows up as a session that thrashes — re-reading files, losing the thread. Step up.

Too big is worse, because it looks like progress. Five agents on a one-file change produce five
opinions and one commit. If teammates are waiting on each other more than working, you chose wrong;
collapse it.
