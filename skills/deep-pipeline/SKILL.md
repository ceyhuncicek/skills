---
name: deep-pipeline
description: Spawn a deep research multi-agent development pipeline (Research → Dual-PM Planning → parallel Coders → Reviewer) for implementing features with high fidelity. Unlike the standard pipeline, this skill runs dedicated codebase and domain research agents before planning, then uses an Actor-Critic dual-PM pattern (PM-Architect proposes, PM-Critic challenges) to produce detailed plans with exact signatures, data flows, and edge cases. Use when the user says "run the deep-pipeline", "use deep-pipeline for X", or wants higher-quality plans with fewer review rounds. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json.
metadata:
  version: "1.0.0"
---

You are the **team lead**. Your job is to coordinate — not to write code yourself. Spawn teammates and manage the flow between them.

---

## Phase 0 — Align with the User

Before spawning anyone, ask the user these questions (all at once, not one by one):

1. **Acceptance criteria** — How will we know this feature is done? What should it look like or do?
2. **Patterns to follow** — Are there existing components or files in the codebase to reference or stay consistent with?
3. **Hard constraints** — Anything we must NOT change or touch?
4. **Domain unknowns** — Are there any external APIs, libraries, or concepts you're unsure how to use? (Research-Domain will investigate these.)

Wait for answers before proceeding. If the user says "just do it" or skips a question, use reasonable defaults based on CLAUDE.md.

---

## Phase 1 — Research Phase

After alignment, **before spawning any research agents**, check whether research docs already exist:

```bash
ls -la docs/pipeline/research-codebase.md docs/pipeline/research-domain.md 2>/dev/null
```

- If **both exist**: read them briefly to verify they're relevant to this task. If they cover the same codebase area, **skip Phase 1 entirely** and go straight to Phase 2 using the existing docs. Tell the user: "Reusing existing research docs from previous run."
- If **one or both are missing or clearly irrelevant**: spawn the missing research agent(s) only.

When spawning research agents, do so **in parallel** (single turn):

### Research-Codebase Agent spawn prompt:
```
You are Research-Codebase. Your job is to produce ground-truth facts about this codebase that a PM will use to write a detailed implementation plan. Do NOT implement anything.

Task: {TASK_DESCRIPTION}
Alignment notes: {USER_ANSWERS_FROM_PHASE_0}

Steps:
1. Read CLAUDE.md and ARCHITECTURE.md (if it exists) for project conventions
2. Find existing features similar to what's being built — read those files completely
3. For every file the implementation will likely touch, read it and document:
   - Exact TypeScript types and interfaces relevant to this task
   - Function signatures the implementation will call or extend
   - State management patterns (Zustand store shape, actions)
   - Any conventions or invariants that must be preserved
4. Identify all edge cases visible from the existing code (e.g. null states, loading states, error paths, mobile-only behavior)
5. Note any gotchas: things that look obvious but have hidden constraints

Write your findings to docs/pipeline/research-codebase.md using this format:

---
# Codebase Research: {TASK_DESCRIPTION}

## Relevant Existing Files
- `path/to/file.ts` — [what it does, why it's relevant]

## Key Types & Interfaces
```typescript
// exact types from the codebase the implementation will use
```

## Function Signatures
```typescript
// exact signatures from existing code
```

## State Management
[Zustand store shape, relevant actions, how state flows]

## Similar Existing Features
[What already exists that this should stay consistent with, with file paths]

## Edge Cases & Constraints
- [edge case] — [where it comes from in the code]

## Gotchas
- [thing that looks simple but isn't, with explanation]
---

When done, message the lead: "Research-Codebase done. docs/pipeline/research-codebase.md written."
```

### Research-Domain Agent spawn prompt:
```
You are Research-Domain. Your job is to research external best practices, APIs, and patterns relevant to this task. Do NOT implement anything.

Task: {TASK_DESCRIPTION}
Alignment notes: {USER_ANSWERS_FROM_PHASE_0}
Domain unknowns the user flagged: {DOMAIN_UNKNOWNS_FROM_PHASE_0}

Steps:
1. Identify what external knowledge is needed: browser APIs, React patterns, UI/UX conventions, library APIs, accessibility requirements, performance considerations
2. Web search for best practices and up-to-date documentation for each area
3. For any library APIs or browser APIs in scope, find the exact method signatures and gotchas
4. Look for known anti-patterns or common mistakes for this type of feature
5. Note any relevant accessibility or mobile-first considerations

Write your findings to docs/pipeline/research-domain.md using this format:

---
# Domain Research: {TASK_DESCRIPTION}

## Best Practices
- [practice] — [rationale, source]

## API Reference
[Exact method signatures, parameters, return types for any external APIs in scope]

## Anti-Patterns to Avoid
- [anti-pattern] — [why it's bad, what to do instead]

## Accessibility & Mobile Considerations
- [consideration] — [how to address it]

## Open Questions Resolved
[Answers to domain unknowns the user flagged]
---

If no domain unknowns were flagged and the task is purely internal, write a brief doc noting that and focus on React/TypeScript best practices relevant to the task.

When done, message the lead: "Research-Domain done. docs/pipeline/research-domain.md written."
```

**Wait for BOTH research agents to report before proceeding to Phase 2.**

---

## Phase 2 — Dual-PM Planning (Sequential)

After both research agents report, spawn **PM-Architect first**. Only after PM-Architect reports, spawn **PM-Critic**.

### PM-Architect Agent spawn prompt:
```
You are PM-Architect. Your job is to write a detailed implementation plan. Do NOT implement anything.

Task: {TASK_DESCRIPTION}
Alignment notes: {USER_ANSWERS_FROM_PHASE_0}

Required reading before planning:
1. docs/pipeline/research-codebase.md — exact types, signatures, edge cases from codebase research
2. docs/pipeline/research-domain.md — best practices and external API knowledge
3. CLAUDE.md — project conventions

Steps:
1. Read all three documents above completely
2. Break the task into 3-5 concrete implementation subtasks
3. For each subtask, use the research docs to specify:
   - EXACT files to create or modify (no guessing — cite research-codebase.md)
   - EXACT function/component signatures to write
   - EXACT types to use or create (copy from research if available)
   - Data flow: what goes in, what comes out, what side effects occur
   - Edge cases this subtask must handle (cite research-codebase.md findings)
4. Group subtasks into tracks: subtasks that share any file go in the same track; subtasks with completely different files go in different tracks (max 3 tracks)
5. Note any dependencies between subtasks within a track (sequential ordering)

Write your plan to docs/pipeline/draft-plan.md using this format:

---
# Draft Plan: {TASK_DESCRIPTION}
## Acceptance Criteria
[from alignment]

## Research Citations
- Codebase: [key findings that shaped the plan]
- Domain: [key findings that shaped the plan]

## Track 1 — Files: [file-a.ts, file-b.ts]
### Subtask 1.1: [concrete description]
- File: `path/to/file.ts` (create|modify)
- Signature: `functionName(param: ExactType): ReturnType`
- Types: [exact types to use]
- Data flow: [input → transformation → output]
- Edge cases: [list from research]

### Subtask 1.2: [concrete description] (depends on 1.1)
[same structure]

## Track 2 — Files: [file-c.tsx]
[same structure]

## Constraints
[from alignment + research gotchas]
---

Note: If all subtasks touch shared files, put everything in Track 1.

When done, message the lead: "PM-Architect done. N tracks. Draft at docs/pipeline/draft-plan.md"
Replace N with the actual number of tracks.
```

**Wait for PM-Architect to report before spawning PM-Critic.**

### PM-Critic Agent spawn prompt:
```
You are PM-Critic. Your job is to challenge the draft plan and identify weaknesses. Do NOT implement anything and do NOT rewrite the plan — produce a structured critique only.

Task: {TASK_DESCRIPTION}

Required reading:
1. docs/pipeline/draft-plan.md — the plan to critique
2. docs/pipeline/research-codebase.md — ground truth about the codebase
3. docs/pipeline/research-domain.md — ground truth about external best practices

For each issue you find, classify it as:
- **Critical**: Plan is wrong or will break something (must fix before coding)
- **Gap**: Something the plan doesn't address that it should (missing edge case, missing file, incomplete spec)
- **Minor**: Style, convention, or nice-to-have improvement

Check for:
- Signatures or types that contradict research-codebase.md findings
- Edge cases identified in research that the plan doesn't address
- Anti-patterns from research-domain.md that the plan would introduce
- Subtasks that are underspecified (coder would have to guess)
- Track groupings that would cause merge conflicts (shared files in different tracks)
- Missing integration points (a file that needs to be updated but isn't in the plan)
- Constraint violations (things the user said NOT to touch)

Write your critique to docs/pipeline/plan-critique.md using this format:

---
# Plan Critique: {TASK_DESCRIPTION}

## Critical Issues
- [Subtask X.Y] Issue: [what's wrong]. Fix: [specific correction, cite research if applicable]

## Gaps
- [what's missing] — [why it matters] — [suggested resolution]

## Minor Issues
- [description] — [suggested fix]

## Verdict
NEEDS_REVISION | APPROVED_WITH_MINOR_ISSUES | APPROVED

(Use NEEDS_REVISION only if there are Critical Issues. Use APPROVED_WITH_MINOR_ISSUES if only Gaps or Minor Issues exist. Use APPROVED if the plan is solid.)
---

When done, message the lead: "PM-Critic done. Verdict: [VERDICT]. Critique at docs/pipeline/plan-critique.md"
```

**Wait for PM-Critic to report before proceeding to Phase 3.**

---

## Phase 3 — Lead Synthesizes Final Plan

After PM-Critic reports, YOU (the lead) read both docs and write the final plan. This is the only phase where the lead writes content.

1. Read `docs/pipeline/draft-plan.md`
2. Read `docs/pipeline/plan-critique.md`
3. Apply all **Critical Issues** fixes exactly as the Critic specified
4. Apply **Gaps** that are clearly correct and bounded (skip gaps that would substantially expand scope without user approval)
5. Note **Minor Issues** in the constraints section but do not apply them (coders can use judgment)
6. Write the final plan to `docs/pipeline/current-task.md` in the same format as the draft plan, updated with fixes

The final `current-task.md` must use this format (compatible with existing pipeline format):

```
# Task: {TASK_DESCRIPTION}
## Acceptance Criteria
[from alignment]

## Research Summary
- Codebase key findings: [2-3 bullet points]
- Domain key findings: [2-3 bullet points]
- Critic verdict: [VERDICT] — [summary of what was fixed]

## Track 1 — Files: [file-a.ts, file-b.ts]
- [ ] Subtask 1.1: [concrete description with exact signature]
- [ ] Subtask 1.2: [concrete description] (depends on subtask 1.1)

## Track 2 — Files: [file-c.tsx]
- [ ] Subtask 2.1: [concrete description]

## Constraints
[from alignment + research gotchas + unresolved minor issues noted]
```

After writing `current-task.md`, note how many tracks the final plan has (N).

---

## Phase 4 — Spawn Coders + Reviewer

Spawn **N Coder agents** and **1 Reviewer** simultaneously in a single turn.

### Coder-N Agent spawn prompt (one per track):
```
You are Coder-{N} in a parallel development pipeline. You own Track {N}.

Your track:
[paste the Track N section from docs/pipeline/current-task.md]

Steps:
1. Read docs/pipeline/current-task.md for full context and constraints
2. Read CLAUDE.md for project conventions
3. Read docs/pipeline/research-codebase.md — this has exact types and signatures; use them directly instead of guessing
4. Read docs/pipeline/research-domain.md — this has best practices; follow them
5. Read the relevant existing files first — understand before modifying
6. If you still need to understand a library or API not covered in research-domain.md, spawn a subagent to look it up. Do NOT block your main context on slow lookups.
7. Implement all subtasks in your track in order
8. When your track is fully implemented, message the lead (not the Reviewer): "Track {N} ready for review. Changed files: [list]"
9. Wait for further instructions from the lead

Project context: Read CLAUDE.md for conventions, patterns, and architecture.
```

### Reviewer Agent spawn prompt:
```
You are the Reviewer for this pipeline. Wait for the lead to direct you.

When the lead tells you a track is ready for review:
1. Run: git diff (to see all changes for that track's files)
2. Use the /code-review skill on the changed files
3. Focus your review on:
   - Correctness: does it do what the subtasks say?
   - Consistency: does it follow CLAUDE.md conventions?
   - Regressions: does anything break?
   - Mobile-first layout (max-w-md)
   - TypeScript types (no `any` unless justified)

4. In addition to /code-review, manually scan the diff for these specific patterns:

   **Dead code / unreachable branches:**
   - Render branches that can never trigger
   - State variables that are set but never read, or read but never set
   - Props accepted but never used inside the component

   **React correctness:**
   - `setTimeout` / `setInterval` calls with no `useEffect` cleanup
   - `useCallback` / `useMemo` dependency arrays — missing or over-specified deps
   - Stale closure risks in delayed callbacks

   **Completeness in new files:**
   - `LocalizedString` objects missing language keys — for NEW files, treat missing translations as a fixable issue
   - "Pre-existing pattern in a new file I just created" is NOT a valid excuse

   **Research alignment:**
   - Compare implementation against docs/pipeline/research-codebase.md — does it match the expected types and signatures?
   - Compare against docs/pipeline/research-domain.md — does it follow the documented best practices?

5. Write a structured fix plan to docs/pipeline/review-track-{N}-round-{R}.md:

---
# Review: Track N, Round R
## Concerns
- [file:line] Issue: ... Fix: ...
## Potential Issues
- [description, risk level]
## Approved Items
- [what looks good]
---

6. Message the lead (not the Coder): "Review complete for Track N Round R. Fix plan at docs/pipeline/review-track-N-round-R.md"
   - If no issues found, write "APPROVED" in the fix plan and message lead: "Track N approved."

Be thorough but fair. Don't block on style preferences — only real issues.
```

After spawning all agents, message each Coder: "You own Track N. Start implementing."

---

## Phase 5 — Coordinate Review Loops

For each track, when the Reviewer reports a review is complete:

**If fixes needed:** Spawn a **fresh Coder** for the fix pass (clean context):
```
You are a Coder doing a focused fix pass. You have no prior context on this implementation.

Read these files only:
1. docs/pipeline/current-task.md — for the original task requirements
2. docs/pipeline/review-track-{N}-round-{R}.md — for the specific issues to fix
3. The changed files listed in the review doc

Apply every fix listed in the "Concerns" section exactly as described. Do not refactor beyond what's asked.

When done, message the lead: "Fix pass complete for Track N Round R. Ready for re-review."
```

Then tell the Reviewer: "Please re-review Track N. Fix pass is complete."

**If approved:** Note that Track N is done. When ALL tracks are approved, proceed to Phase 6.

Track review loops run in parallel — don't wait for Track 1 to finish before starting Track 2's review loop.

---

## Phase 6 — Final Report and Commit

When all tracks are approved:

1. Generate a final report at `docs/pipeline/YYYY-MM-DD-[kebab-task-name].md` (use today's date):
```
# Deep-Pipeline Report: [Task Name]
Date: YYYY-MM-DD

## What Was Built
[1-2 sentence summary]

## Research Findings That Shaped the Plan
- Codebase: [key finding that changed the plan]
- Domain: [key finding that changed the plan]

## Critic Verdict
[VERDICT from plan-critique.md] — [what was revised as a result]

## Changes
- [file] — [what changed]

## Tracks
- Track 1: [subtasks] — N review rounds
- Track 2: [subtasks] — N review rounds

## Plan Deviations
[Anything implemented differently from current-task.md, and why]

## Open Questions / Follow-ups
[Anything deferred or noted during review]
```

2. Delete the **task-specific** working files (these are throwaway planning artifacts):
   - `docs/pipeline/current-task.md`
   - `docs/pipeline/draft-plan.md`
   - `docs/pipeline/plan-critique.md`
   - All `docs/pipeline/review-*.md` files
   - `docs/pipeline/README.md` (if it exists)

   **Do NOT delete** the research docs — they are project knowledge assets, not working files:
   - `docs/pipeline/research-codebase.md` — keep (valuable for future sessions and follow-up tasks)
   - `docs/pipeline/research-domain.md` — keep (valuable for future sessions and follow-up tasks)

3. Create one commit:
   - Stage all code changes + the final report file + deleted working files
   - Commit message: `feat: [task name] (deep-pipeline)`

4. Shut down all teammates: send shutdown requests to each active agent, then wait **at most 10 seconds** for responses. If any agent doesn't respond, proceed anyway — do not block the final report on unresponsive agents. Silent agents at teardown are a housekeeping non-issue.

5. Report to the user: what was built, files changed, research findings that mattered, critic verdict, any open questions.

---

## Lead Coordination Rules

- **Don't do the coding yourself** — your value is coordination and synthesis
- **Research agents run in parallel** — spawn both in a single turn, wait for both before Phase 2
- **PM phases are sequential** — PM-Architect first, then PM-Critic after Architect reports
- **Lead writes current-task.md directly** — Phase 3 synthesis requires judgment calls; don't delegate
- **Spawn all Coders at once** after writing current-task.md (one turn, parallel)
- **Coders read research docs** — they have exact types and signatures; coders should use them directly
- **Fresh Coder per review round** — each fix pass gets a new agent with clean context
- **Reviewer messages the lead, not Coders** — lead is the hub; Coders never talk to Reviewer directly
- **Max 3 Coders** — beyond that, coordination overhead exceeds benefit; consolidate tracks
- If a research agent, PM, or Coder goes silent, nudge them directly
- If review loops exceed 3 rounds on the same track, intervene and make a judgment call
- If PM-Critic's verdict is NEEDS_REVISION with many critical issues, consider whether to re-run PM-Architect (rare — only if the draft is fundamentally wrong)
