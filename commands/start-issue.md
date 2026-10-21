---
description: "Take an issue from a worktree to a merge request, stopping twice for approval"
argument-hint: "<issue-id> [extent]"
allowed-tools: ["Bash", "PowerShell", "Glob", "Grep", "Read", "Write", "Edit", "Agent", "Skill", "LSP"]
---

# Start an issue

Take issue `$ARGUMENTS` to an open MR. Stop for the user exactly twice: at the plan (step 5) and at
the pushed commits (step 11). Do everything in between without asking.

- The first token is the issue id.
- A second token of `session`, `subagents`, `team` or `workflow` is the extent: it replaces step 3's
  choice, and counts as the user's yes for a team or a workflow.
- Anything else is the user's **note** (Helm passes what was typed when the issue was started). It
  outranks this file, and the architect gets it with the issue.

You orchestrate; the agents do the work. Your context is for judgement: choose the questions, weigh
the answers, check the plan, route findings. Leave the reading, test writing, coding and reviewing to
the agents.

## The progress file

Keep `<worktree>/.flow-state.json` current. Helm reads it, and a resumed session
starts from it.

```json
{"issue": 128, "branch": "me/128-slug", "step": 6, "name": "tester", "status": "active", "extent": "subagents", "at": "2026-09-14T10:12:00Z"}
```

| step | name | step | name | step | name |
| --- | --- | --- | --- | --- | --- |
| 1 | `issue` | 5 | `plan-gate` | 9 | `gate-build` |
| 2 | `worktree` | 6 | `tester` | 10 | `format` |
| 3 | `extent` | 7 | `implementer` | 11 | `commits-gate` |
| 4 | `plan` | 8 | `review` | 12 | `mr` |

- `active`: written when a step starts.
- `done`: written when it ends.
- `waiting`: written at a gate (5 and 11), just before you stop. On approval, write the next step
  `active` immediately.
- `skipped`: a step that does not apply this time, with the reason in one line.

Write it atomically (`.flow-state.json.tmp`, then `mv -f`), with `issue`, `branch` and a UTC `at` in
every write. The first write is step 2 `done`. Before it, make sure `.flow-state.json`,
`.flow-state.json.tmp` and `.flow-plan.md` are each listed in the exclude file git reads,
`"$(git rev-parse --git-path info/exclude)"` (the shared one, also for a worktree); append only the
lines it does not already have.

**Resuming.** If the issue's worktree already has the file, say in one line where you resume:

- `done` or `skipped`: start the next step.
- `active`: the step was interrupted; finish what it left.
- `waiting`: show the plan or the commits again and wait.

## Agents and models

Launch every agent with its model from `models` in the config, as the `model` parameter of the Agent
call. A missing or null entry passes nothing.

| Agent | Model key | Pass it |
| --- | --- | --- |
| `flow:researcher` | `models.research` | one area and one question |
| `flow:architect` | `models.architect` | the issue with its comments, the briefs, the plan path |
| `flow:tester` | `models.build` | the plan path, `verify.targeted`, the lock script path |
| `flow:implementer` | `models.build` | the plan path, the failing tests, `verify.syntaxCheck`, `verify.targeted`, the lock script path |
| `code-simplifier` | `models.review` | the production files from the plan |
| `flow:reviewer` | `models.review` | the base ref, the plan path, `review.floor`, `review.mute` |
| `flow:mr-creator` | `models.mr` | the issue, the branch, the `mr` config |

An agent sees only what you pass it. Give paths, not summaries: an agent reads the plan itself.

## Builds

Run every build through the lock script, yours and the agents':

```
sh "${CLAUDE_PLUGIN_ROOT}/scripts/with-build-lock.sh" <build command>
```

It waits while another build (Helm's, or another agent's) holds the build tree.

- **A `skill:` entry** in `verify` names a skill. Load it, take the exact command it gives, and run
  that command through the lock script. Never write your own build script in its place.
- **Long builds run in the background** (`run_in_background`), output to a log in the git dir. Until
  the completion notice arrives, do not read the log, sleep or check on it. When it arrives, read
  only the log's tail, and only if the build failed.
- **A gate this machine cannot run**, such as an Xcode build on Windows: mark it `skipped (host)` in
  one line and go on. CI builds it.

## 1. Config and issue

Read `.claude/flow.json`, else `~/.claude/flow.local.json`. If neither exists, stop and name the file
to create from `flow.config.example.json`. Never guess a project, a branch or a command.

```
glab api "projects/<enc>/issues/<id>"            # forge: glab
gh issue view <id> --json title,body,comments    # forge: gh
```

Read the description and every comment. The comments usually narrow what is wanted.

## 2. Worktree

- Slug: the issue title, lowercased, non-alphanumerics to `-`, repeats collapsed, at most ~50 chars.
- Branch: `branchPattern`. Path: `<worktreeRoot>/<issue>`.

```
git fetch origin <defaultTarget>
git worktree add <worktreeRoot>/<issue> -b <branch> origin/<defaultTarget>
```

When a worktree for this issue already exists, use it; never create a second one:

- It holds this issue's progress file: resume (see the progress file above).
- You were started inside it (Helm makes the worktree and its branch before it starts you): it is
  yours. Carry on from here without asking.

From here on, work only in the worktree.

**Start the early build now**, in the background: every `verify.gate` command in turn, build only,
each through the lock script.

```
gd=$(git rev-parse --absolute-git-dir)
{ sh "${CLAUDE_PLUGIN_ROOT}/scripts/with-build-lock.sh" <gate command 1>
  sh "${CLAUDE_PLUGIN_ROOT}/scripts/with-build-lock.sh" <gate command 2>
} > "$gd/flow-early-build.log" 2>&1
```

It builds the untouched target branch so that later builds are incremental. When its notice comes,
say in one line whether it passed. A failure here is the target's or the machine's, not this change's.
On a resume, start it only if the build tree was never built.

## 3. Extent

Invoke the `extent-router` skill with the issue. Size from what the issue and its comments say, plus
at most a few cheap looks of your own (one `Grep` count, one `LSP` references call). Launch no agents
here: reading the code is step 4's job, and its researchers report the size too. Typical outcomes:

- One class, one behaviour → subagents, the default chain below.
- A feature on several platforms that must agree on one interface (a Windows view and an iOS view
  over one model) → an agent team, one teammate per platform.
- A mechanical change across hundreds of files, or a design hard enough to draft from three
  independent angles and compare → a workflow.

Record the choice as `"extent"` in every later write of `.flow-state.json`, so a resumed session
keeps it. For `session` or `subagents`, continue without comment. For a team or a workflow, show the
choice, the agent count and a rough token cost, and wait for a yes; on a no, record `subagents`.

What the extent changes in the steps below; everything not named stays as written, the gates
included:

| Extent | Step 4 | Steps 6 and 7 | Step 8 |
| --- | --- | --- | --- |
| `session` | Read the one to three files yourself; the architect still writes the plan | Tester and implementer as written | As written |
| `subagents` | As written | As written | As written |
| `team` | As written; the plan names one strand per teammate and the interface they share | One teammate per strand, each running tester then implementer on its own files; you lead and settle the shared interface | One reviewer over the whole diff, after every strand is green |
| `workflow` | As written; the plan names the batches and the check each must pass | A workflow script: one implementer per batch, then a verifier per batch running `verify.targeted` | One reviewer over a sample of batches plus every batch a verifier failed |

**Correcting course.** When the briefs of step 4 show a larger job than step 3 sized (many more
files, a second platform, a sweep), route again before tasking the architect, and ask as above if
the new extent is a team or a workflow.

## 4. Research, then plan

**Research in parallel.** Launch one `flow:researcher` per area, all in one message. Usually three to
five. Example questions for an issue about token refresh:

- "How does `src/Auth` store and refresh tokens today? Every call site of `TokenStore`."
- "What do the tests in `Tests/Auth` use as doubles for the network and the store?"
- "Find a past change that added a persisted store: which files did it touch?"

A one-file issue can take one researcher, or none if you already know the file.

**Plan.** Task `flow:architect` with the issue, the briefs and the plan path `<worktree>/.flow-plan.md`.
It writes the plan there. Read it yourself before the gate. Send it back with your objection if it
contradicts the issue thread, leaves an issue comment unanswered, or names files the briefs never
mentioned.

## 5. ■ Gate 1: the plan

Write `waiting`. Tell the user, in at most five lines, what the plan changes and its open questions,
and that the full plan is in `.flow-plan.md` (Helm's **Plan** button). Then stop.

- Any clear yes approves. Helm's **Approve plan** button sends "The plan is approved. Continue.",
  possibly followed by a note: take the note into account.
- An open question the approval does not answer takes its recommended option.
- A different answer, or a change of shape: re-task `flow:architect` with the decision, so it rewrites
  `.flow-plan.md`, and continue only once the plan matches. Never build on a plan that says something
  else.

Answer design questions directly. On approval, write step 6 `active` (or `skipped`) first.

## 6. Tester: red

Task `flow:tester`. It builds one target with `verify.targeted`, never the whole project. Tests must
fail because the behaviour is missing, not because they do not compile.

An empty test list in the plan: write step 6 `skipped` ("no behaviour to test: a comment fix") and go
on.

## 7. Implementer: green

Task `flow:implementer`. It never edits the tests. Loop tester and implementer until green. After
three rounds without green, stop and tell the user why; the plan is probably wrong.

## 8. Self-review

On the branch's diff against `origin/<defaultTarget>`:

1. **Simplify.** Task `code-simplifier` with the production files from the plan, and tell it: same
   behaviour, no test changes, no new comments. Re-run `verify.targeted`; undo any part that turns a
   test red. If the plugin is not installed, say so in one line and skip it.
2. **Start the gate build** in the background, as step 9 runs it, into `"$gd/flow-gate-build.log"`.
   Record what it builds:
   ```
   { git rev-parse HEAD; git status --porcelain; git diff HEAD
     git ls-files -o --exclude-standard -z | xargs -0 cat; } 2>/dev/null | git hash-object --stdin
   ```
3. **Review and security, in parallel** while it builds:
   - Task `flow:reviewer` on the full diff.
   - If the diff touches input parsing, authentication, permissions, file paths, shell or SQL built
     from data, deserialization, secrets or network handling: invoke the `security-review` skill.
     Otherwise say in one line that it does not apply.

Send each finding that is not in `review.mute` back through the chain: a behaviour change goes to the
tester and then the implementer, anything else to the implementer.

## 9. Gate build

Every command in `verify.gate` must pass. The gate build from step 8 is the first run:

- Still running: say so in one line and wait for its notice.
- Passed, and the hash from step 8 still matches: the gate has passed.
- Otherwise, because of a failure or a later fix: run the gate again through the lock script. It
  rebuilds only what changed.

A session resumed at this step has no notice coming: run the gate.

## 10. Format, last

Formatting rewrites mtimes and forces a full rebuild, so it runs once, here.

Run `verify.format`, then every entry in `verify.extra` whose condition (after its `#`) holds. Write
the stamp in the same command as the formatter, never on its own:

```
<formatter command> && touch "$(git rev-parse --git-dir)/flow-formatted"
```

The stamp tells the commit gate that formatting ran. Touching it without formatting ships
unformatted code. When `verify.format` asks for one tree-wide run, prefix that run with
`FLOW_TREEWIDE_OK=1`; the guard is there to stop a second one. With no `verify.format`, write step 10
`skipped` and touch the stamp alone.

## 11. ■ Gate 2: the commits

The user reads the series one commit at a time in Helm's **Review commits** page, and the MR keeps
the series as it is.

1. **Shape the series.** Replace the working history (red, green, review fixes, formatting) with the
   commits that land. No editor can open, so: `git reset --soft origin/<defaultTarget>` and
   recommit, or `git commit --fixup=<sha>` and then
   `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<defaultTarget>`.
   - Each commit does one thing. Tests go with the code they test. A rename stays apart from a
     behaviour change. No commit fixes an earlier one.
   - Order: independent fixes and refactors, then building blocks, then the change that uses them.
   - Messages: one line, imperative, `{issue} - What this commit does`.
   - A small change is one commit. Example for a three-commit series:
     ```
     4462 - Rename TokenCache to TokenStore
     4462 - Add a file-backed TokenStore
     4462 - Refresh an expired token before each request
     ```
2. **Build the tip** with `verify.targeted` through the lock script. Do not build each commit.
3. **Push.** `git push -u origin <branch>`. If the branch is already on the remote, first
   `git tag backup/<branch>-<stamp>`, then `git push --force-with-lease`. Never a bare `--force`.
4. **Stop.** Write `waiting`. Say in one line how many commits are on the remote and that they are
   under Review commits.

Marks from the Review commits page arrive as one message. Write step 11 `active` and route each mark
like a review finding (step 8). Fold each fix into the commit it belongs to, tag a backup, push with
`--force-with-lease`, and stop again with `waiting`. Open no MR until the user approves; Helm's
**Approve commits** button sends "The commits are approved. Open the merge request."

## 12. MR

On approval: write step 12 `active`, then task `flow:mr-creator`. It opens the MR on the approved
series as it stands, and returns the link. Then write step 12 `done`, and watch the MR's first
pipeline as `/flow:watch-pipeline <mr>` describes: its waiter in the background, costing nothing
until CI finishes.

**Lessons.** With `learn` at `"ask"` (the default), end with one line offering to add what this issue
taught to the project's `CLAUDE.md`. Examples: a convention the reviewer enforced, a build quirk the
gate hit, a test pattern the tester settled on. Only on a yes, invoke
`claude-md-management:revise-claude-md` with those points and show the change before writing it. With
`learn` at `"off"`, or nothing worth keeping, say nothing.
