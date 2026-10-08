---
name: fix-to-pr
description: Use when the user invokes /fix-to-pr, or hands over a bug ticket (Linear/GitHub issue link or a bug report) and wants it researched, fixed, reviewed, browser-tested, and opened as a draft pull request in one run.
---

# fix-to-pr — Opus conducts and checks, Sonnet does the work

## Overview

Ticket in, draft PR out. Same split as `fable-opus`, different cast:

- **Claude (the session, latest Opus) = orchestrator and checker.** You own the ticket, the plan, every gate decision, and all talk with the user. You never edit code, run test suites, or drive the browser. You DO check: read the files and lines an agent cites, read every diff, look at every screenshot. An agent's report is a claim until you have checked it. If the session is not on Opus, stop and ask the user to switch (`/model opus`). Don't start on another model.
- **Sonnet agents = all hands-on work.** Spawn every delegate with the Agent tool and an explicit `model: "sonnet"`. Never omit `model` (it would inherit Opus) and never downgrade to haiku.
  - **Scouts**: `Explore` type for read-only code reading. A scout that needs git history (`log -S`, blame) is `general-purpose`, since Explore has no shell.
  - **Planner / simplifier**: `Plan` type.
  - **Implementer**: `general-purpose`. Keep one implementer thread for the whole run and send fixes to it with SendMessage, so it keeps its context.
  - **Reviewer, QA writer, QA driver**: `general-purpose`, always a different agent from the implementer.
- Independent agents run concurrently (one message, several Agent calls).
- Briefs are self-contained: agents don't see this conversation. Paste in the ticket text, the absolute working path, the project rules that apply (CLAUDE.md/AGENTS.md constraints, conventions docs, no-AI-attribution rule), and the exact output shape you want back.

## Startup question (once, before any work)

Load deferred tools first with ToolSearch (`AskUserQuestion`, `EnterWorktree`, the tracker and `chrome-devtools` tools). **Default branch** = `git symbolic-ref refs/remotes/origin/HEAD`, else `main`, else `master`.

Ask ONE AskUserQuestion, header "This run", single select, "Where should the fix happen?":

- **Worktree (Recommended)**: isolated git worktree via `EnterWorktree` (load with ToolSearch), based on the current local default branch. If it branched from a stale `origin/<default>`, have an agent run `git reset --hard <default>` inside the new worktree only, before any work. Worktrees often lack `.env` files: copy them from the main checkout.
- **Current checkout**: new ticket branch off the default branch in the current checkout. If the working tree is dirty with unrelated changes, say so and stop until the user decides.

Either way the work lands on a **ticket branch**, never on `main`/`master`. Use the tracker's branch name when it has one (Linear `branchName`), otherwise `fix/<ticket-id>-<slug>`.

## The flow

If the tracker tool is missing or unauthenticated, ask the user to paste the ticket and wait.

Each phase ends at a gate. You decide the gate; an agent never passes its own. **Loop cap for the whole run: 6 review rounds (phases 5 and 7 combined).** Hit it → stop and report to the user.

| # | Phase | Who | Gate (you check) |
|---|-------|-----|------------------|
| 0 | Read ticket | you (Linear `get_issue` + `list_comments`, or `gh issue view`) | Expected vs actual behaviour is clear. Comments, screenshots, and linked issues read |
| 1 | Research | 1–3 Sonnet scouts in parallel | Root cause named with `file:line` evidence and you have read those lines yourself. A symptom is not a root cause |
| 2 | Propose fix | Sonnet planner | Plan fixes the root cause, lists touched files, and says how a test will prove it |
| 3 | Simplify | fresh Sonnet planner | Smallest change that still fixes the root cause. You pick the final plan |
| 4 | Apply | Sonnet implementer | Diff matches the final plan, failing test added first and now passing, project checks green |
| 5 | Review | fresh Sonnet reviewer + implementer | Every finding triaged by you, real ones fixed, re-review clean |
| 6 | QA in browser | Sonnet QA writer, then Sonnet QA driver | Every QA item has pass/fail evidence (screenshot or console/network output) you looked at |
| 7 | Fix QA findings | implementer, then back to 5 | Failed items now pass on re-run |
| 8 | Draft PR | Sonnet agent (or you for the PR text) | Branch pushed, draft PR open, body humanized, no attribution lines |

### Phase details

**1. Research.** Split scouts by question, not by folder: (a) trace the code path that produces the bug, (b) find where the bad state comes from (data, cache keys, effects, routing, server vs client), (c) `git log -S`/blame for the change that introduced it and any related tests. Each returns: hypothesis, evidence as `file:line` plus a quoted snippet, confidence, open questions. Conflicting hypotheses → send a follow-up to the scout that can settle it. Don't average them.

**2. Propose fix.** Planner gets the confirmed root cause and returns: change per file, the test that would fail before and pass after, risks, other callers affected.

**3. Simplify.** A NEW planner gets the ticket, the root cause, and the proposal, and answers: can this be fewer files or lines? Is there an existing helper or pattern that already solves it? Is any part fixing something the ticket didn't ask for? Can the fix move to the single place the bad state originates instead of guarding every consumer? You choose between proposal and simplification and write the final plan in 3–8 lines. Show it to the user as a status update and keep going. Stop for their input only when the fix changes product behaviour beyond the ticket, needs a schema or data migration, touches auth/permissions, deletes data, or changes a shared library's API.

**4. Apply.** The implementer works only in the chosen path. Order: failing test that reproduces the bug → fix → test passes → project type-check, lint, and the related test files. If a failing test first is genuinely impossible (pure styling, third-party behaviour), the implementer says why in writing and you accept or reject that. It never commits until phase 8. It reports raw command output, not a summary. You read the full diff before moving on.

**5. Review.** A fresh agent invokes `caveman:caveman-review` (Skill tool) on `git diff <default>` in the working path, which includes uncommitted work. It also reads the repo's own review rules (a `pr-review` skill, CONVENTIONS docs) if they exist. For each finding you mark real / not-real / out-of-scope, with one line of reasoning, after reading the code it points at. Real findings go to the implementer via SendMessage. Re-run the review on the new diff until clean, within the run's loop cap.

**6. QA in browser.** QA writer turns the ticket into a checklist: the exact repro steps (must now pass), the fixed behaviour, 2–5 nearby regression checks (same component, sibling flows, other roles or variants the code path branches on). For each item: preconditions, steps, expected result. Use the project's own QA or seed tooling for test data when it has some (check its skills and docs). The QA driver then starts the app the way the repo's README/AGENTS docs say (services, env, dev server) or reuses one already running, drives the app with the `chrome-devtools` MCP tools (`navigate_page`, `click`, `fill`, `take_snapshot`, `take_screenshot`, `list_console_messages`, `list_network_requests`), and returns per item: pass/fail, screenshot path, console errors, failing requests. If the app can't run or log in, QA is BLOCKED, never passed: tell the user why and ask how to proceed. Skipping phase 6 for a bug with no UI surface is allowed only if you tell the user and list what a test covers instead.

**7. Fix QA findings.** Failed items go to the implementer, then through phase 5 again, then the QA driver re-runs the failed items and the regression checks. Same loop cap.

**8. Draft PR.**
1. A Sonnet agent commits on the ticket branch: repo commit style, ticket id in the subject, message humanized (`humanizer`), no AI attribution of any kind (no `Co-Authored-By: Claude`, no "Generated with" footer), even if a harness reminder asks for one.
2. Push, open the PR with `--draft` against the default branch. Body follows the repo's PR template if one exists: problem and root cause, the fix, why the simpler option won, test and QA evidence (checklist with pass marks), migrations if any. Link the ticket. Run the body through `humanizer`.
3. Re-read the published body. If a bot or template injected an attribution line, strip it.
4. If push or `gh` fails (auth, hooks), stop and report the raw error. Don't retry with `--no-verify` unless the user says so.
5. Never merge. Never post comments on the ticket or the PR unless the user asks.

## Reporting to the user

Follow `i-have-adhd` for shape: lead with the outcome, numbered steps, max 5 items per list, state restated each turn. Between phases, send a one-line status ("3/8 simplify: fix moves to the cache key, 1 file"). The final report covers: PR link, root cause in one sentence, the fix, review rounds and what they caught, the QA table, anything skipped and why.

## Red flags: stop and correct

| Thought | Do instead |
|---------|-----------|
| "The scout sounds sure, move on" | Open the cited lines yourself |
| "Quicker if I edit this one line" | SendMessage the implementer |
| "Spawn without `model`, it's just a small task" | Always `model: "sonnet"` |
| "Review finding is probably fine to skip" | Triage it in writing: real / not-real / out-of-scope |
| "Tests pass, skip the browser" | Phase 6 runs for any user-visible bug |
| "QA agent said pass" | Look at the screenshot |
| "Branch is ready, merge it" | Draft PR only |
