---
name: fable-gpt
description: Use when the user invokes /fable-gpt or asks for the Fable-orchestrator + Codex-executor workflow — Claude plans and reviews, Codex implements.
---

# fable-gpt — Fable orchestrates, Codex executes

## Overview

Split roles between the two models for the rest of the session:

- **Claude (Fable 5) = orchestrator.** Planning, architecture decisions, task decomposition, and final review/judgment stay with you. Do these yourself — never delegate them.
- **Codex = executor.** Heavy implementation, debugging, test fixing, refactoring, and multi-file code edits go to the `codex:codex-rescue` agent, invoked via the `codex:rescue` skill. Prefer the **GPT 5.5 (high)** Codex model.
- **Opus agents or Codex = scouts & verifiers.** Repo searches/exploration and verification runs (test suites, syntax checks, sweeps for stale references, server restarts) go to a delegate: either an Opus subagent (Agent tool, `model: "opus"`; Explore agent type for read-only sweeps) or Codex via `codex:rescue`. Pick whichever fits — Opus for repo-context-heavy sweeps, Codex when the check is self-contained or Codex just wrote the code being checked is fine too. Fable reads their reports and makes the call — the judgment stays with Fable, the legwork goes to the delegate.

## Workflow

1. Understand the task first. Delegate the code searching/reading to a scout (Opus agent or Codex); you synthesize their findings into the plan.
2. Decompose into focused, specific Codex tasks — one well-scoped task per delegation, with the exact files, constraints, and acceptance criteria spelled out. Include relevant project rules (e.g. CLAUDE.md constraints, definition-of-done checklists) in the delegation prompt.
3. Delegate implementation via `codex:rescue`, requesting GPT 5.5 (high).
4. **Verify via a delegate, judge yourself.** Spawn an Opus agent or a Codex task to run tests/syntax checks/behavior checks (and, where project policy allows, restarts) and report raw results. Prefer a DIFFERENT delegate than the one that wrote the code when practical (fresh eyes). Read the diff and the verification report yourself before accepting. If it's wrong or incomplete, send a corrective follow-up task or fix small issues directly.
5. You own the final review and the report back to the user.

## When NOT to delegate

- Trivial edits (a few lines, one file) — faster to do directly.
- Planning, architecture calls, or anything requiring conversation context the delegate doesn't have.
- The final accept/reject judgment — a delegate runs the checks, but reading the results and deciding is always yours.
