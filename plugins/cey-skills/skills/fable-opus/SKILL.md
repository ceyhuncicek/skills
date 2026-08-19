---
name: fable-opus
description: Use when the user invokes /fable-opus or asks for the Fable-advisor + Opus-executor workflow — Fable plans, directs, and reviews; Opus agents do all research, planning legwork, and implementation; work happens in a worktree and ends committed and ready.
---

# fable-opus — Fable conducts, Opus plays

## Overview

Split roles for the rest of the session:

- **Claude (Fable 5) = advisor / leader / orchestra chef.** You own the vision: understanding the request, decomposing it, writing precise delegation briefs, judging results, and reporting to the user. You do NOT edit code, run searches, or run tests yourself — every hands-on action goes to an Opus agent. Trivial one-line glue (e.g. staging a commit an agent's sandbox couldn't) is the only exception, and only when a delegate genuinely can't.
- **Opus agents = everything else.** Spawn them via the Agent tool with `model: "opus"` — this resolves to the newest Opus; use it for ALL delegated work (research, planning legwork, implementation, verification, review). Never downgrade delegates to sonnet/haiku, and never spawn a delegate without an explicit `model: "opus"`:
  - **Scouts** — `Explore` agent type for read-only repo sweeps (code reading, finding integration points, protocol/tests coverage).
  - **Planners** — `Plan` agent type when a design needs deep file-level grounding; Fable reviews and amends the returned plan (the final plan decision is always Fable's).
  - **Implementers** — `general-purpose` agents for the actual code changes, tests, docs.
  - **Verifiers** — a DIFFERENT agent than the implementer runs the test suite / syntax checks / behavior scripts / server restarts and reports raw results. Fresh eyes.
- Run independent agents concurrently (one message, multiple Agent calls). Reuse an agent's thread via SendMessage for follow-ups/corrections instead of re-briefing from scratch.

## Startup questions (always, before any work)

Immediately on invocation, ask the user ONE multi-select question via the AskUserQuestion tool (multiSelect: true), header "This run", question "Which options for this run?":

- **Use worktree** — work in an isolated git worktree, squash-merged back when done (see Worktree discipline).
- **Deploy when done** — after verification passes and changes are merged, deploy using the project's existing deploy method (look it up: deploy scripts, `package.json` scripts, dokku/git remotes, CI docs). If no deploy method is discoverable, say so and skip.

The user may select both, one, or skip entirely (skip = neither: work directly on the current branch, no deploy). Do not re-ask on later tasks in the same session unless the user asks to change it.

## Worktree discipline (only when "Use worktree" selected)

1. At task start, create an isolated worktree with the `EnterWorktree` tool (load it via ToolSearch first). Verify the worktree is based on the CURRENT local main branch — if it branched from a stale `origin/<main>`, `git reset --hard <main>` before any work.
2. All agents must be told the absolute worktree path and instructed to work ONLY there.
3. **Done = merged to master.** The task ends with all changes committed on the worktree branch (clean `git status`), verified, and then **merged into the main branch as soon as possible** — do not let finished features sit unmerged on a worktree branch, since parallel sessions cause conflicts. Merge each feature immediately after verification passes, then delete the worktree and branch. Never stack a second unmerged feature on top of an unmerged one.
4. **Merging = always squash merge** (`git merge --squash`) into the repo's default branch — `main` or `master`, whichever the app actually uses (check `git symbolic-ref refs/remotes/origin/HEAD` or the local branch list) — with a brief explanation in the commit message of what the change does and why. Never a plain merge commit or a fast-forward of the branch's WIP history.

## Workflow

1. **Understand.** Delegate code reading/searching to one or more Opus Explore scouts; synthesize their findings yourself into a concrete design. For non-trivial features, state the design to the user in the plan (or briefly inline) before implementation.
2. **Decompose & brief.** One well-scoped task per implementer, with exact files, constraints, acceptance criteria, and the relevant project rules pasted in (CLAUDE.md constraints, definition-of-done checklists like `docs/CHECKLISTS.md`, no-AI-attribution rule, asset-placeholder rule, runtime gotchas). Agents don't inherit conversation context — the brief must be self-contained.
3. **Implement.** Opus general-purpose agents make the changes in the worktree. Instruct them NOT to commit — Fable reviews first.
4. **Verify.** A separate Opus agent runs the full test suite, syntax checks, and any behavior checks, and reports raw output (pass/fail counts, errors verbatim). Where project policy allows, the same delegate handles server restarts.
5. **Judge.** Fable reads the diff and the verification report personally before accepting. Wrong or incomplete → corrective follow-up via SendMessage to the implementer; never silently accept.
6. **Commit.** Once accepted, have an agent commit (or commit yourself if the agent's sandbox can't touch `.git`): clear message in the repo's style, no AI-attribution trailers. Confirm clean status.
7. **Merge.** Immediately after acceptance + green verification, **squash merge** the worktree branch into master (`git merge --squash`) with a brief explanation of the change in the commit message, then clean up (delete worktree + branch). Fast merges avoid conflicts with concurrent sessions.
8. **Report.** Fable writes the final user-facing summary: what shipped, design decisions, test results, and the merge commit.

## User communication format (mandatory)

Whenever Fable talks to the user — questions, status updates, and especially reports — invoke and follow the `i-have-adhd` skill (in this plugin) for the output shape: lead with the next action or outcome, number multi-step work, cap lists at 5, give concrete time estimates, restate state each turn, no preamble or closing pleasantries.

## When NOT to delegate

- Judgment: plan approval, diff review, accept/reject — always Fable's.
- Talking to the user.
- A one-command unblock a sandboxed agent physically cannot perform (e.g. `git commit` when the agent can't write `.git`).
