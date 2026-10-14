---
name: pr-pending-review
description: Use when given a GitHub PR link or number and asked to review it - runs an Opus-delegated investigation, ranks findings, and leaves them as PENDING (unsubmitted) inline review comments on GitHub (or approves the PR when nothing red or yellow turns up) written short and kind in a teammate's voice (i-have-adhd shape, humanizer pass, varied openers instead of "is this intended?" on every comment).
---

# pr-pending-review

Input: a PR URL or number. Output: a pending GitHub review the user submits themselves, plus a terse chat summary. When the review finds nothing red or yellow, the output is an approval instead (section 5b).

Never submit a review that has comments. Never request changes. The only `event` ever sent is `APPROVE`, and only on the clean path in section 5b; a review with comments always omits `event`.

## 1. Pull the PR

```bash
gh pr view <n> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles
gh pr diff <n> > $SCRATCH/pr<n>.full.diff
gh pr diff <n> --name-only
```

Split source from tests so the source diff can be read in full:

```bash
awk '/^diff --git/{p=0} /^diff --git a\/(apps\/[^/]+\/src|libs\/[^/]+\/src)/{p=1} p' $SCRATCH/pr<n>.full.diff > $SCRATCH/pr<n>.src.diff
```

Read the source diff yourself. Read the test diff too. Check `gh pr view <n> --json commits` — deleted test files that the commit message does not mention are the highest-value finding in most PRs.

## 2. Delegate investigation to Opus scouts

Spawn 2+ `Explore` agents with `model: "opus"` in ONE message so they run concurrently. Typical split: one backend/domain scout, one frontend/wiring scout.

Briefs are self-contained — agents inherit no context. Each brief carries:
- absolute repo path, "read-only, modify nothing"
- the relevant diff hunks pasted inline (agents cannot see the PR)
- numbered questions, each demanding `file:line` evidence
- the specific doubts you want killed: does the called helper have the semantics assumed here, does the route target page exist, is the removed guard dead code elsewhere, does the type still compile, what breaks at publish/apply time

While they run, verify the cheap things yourself with grep and sed: helper implementations, `classNames` vs `twMerge` behaviour, page files on disk, type derivations.

Judge the results. Scouts are wrong sometimes; drop findings you cannot confirm from the code.

## 3. Rank findings

- red: broken behaviour, lost coverage, will cause an incident
- yellow: works but fragile — race, stale cache, missing guard
- blue: style, naming, micro-optimisation
- question: genuine uncertainty about intent

Chat summary uses caveman-review format, one line per finding: `<file>:L<line>: <colour>: <problem>. <fix>.` No throat-clearing, no restating the diff, exact symbol names in backticks.

## 4. Write the GitHub comments

Only red and yellow findings become comments, unless the user asks otherwise.

No red or yellow findings at all: skip sections 4 and 5 and go to section 5b. Blue findings and questions do not block approval; they stay in the chat summary.

The comment should read like a teammate who spotted something and is checking in, not like a checklist that ran. Kind, short, and in the reviewer's own voice. The author decides; you are asking.

### Shape (`i-have-adhd`)

Invoke `i-have-adhd` and apply its rules to each comment:

1. **First sentence is the point.** What you noticed, at a named spot (symbol or behaviour in backticks). After one line the author knows where to look and what might go wrong.
2. **One problem per comment.** When a finding has several consequences, keep the one the author is most likely to hit in production. The others get their own comment if they are red or yellow on their own, otherwise they go in the chat summary. No "also" paragraphs.
3. **One sentence of mechanism, one `file:line`.** The full trace stays in the chat summary; the author will ask if they want it.
4. **End with the fix as a question**, or skip the fix when it is obvious from the first line.

Budget: aim for **150–300 characters**, hard cap **400**. Over the cap means the comment is carrying more than one problem or more than one sentence of trace.

### Pick the opener by situation

"Is it intended that…" on every comment reads like a bot. Ask about intent only when the code could plausibly be deliberate (a behaviour change, a trade-off, a removed guard). When it is plainly a slip (a crash, a wrong variable, a missed field), an intent question sounds sarcastic. Say what you saw and give the author an easy out instead.

| Situation | How to open | Examples |
|-----------|-------------|----------|
| Could be on purpose | intent, with an easy out | "Was dropping the reload on publish on purpose, or did it slip in?", "Did you mean for `countryCode` to skip the pick check? Totally fine if so, just checking." |
| Looks like a slip | heads-up, no intent question | "Not sure if you've hit this yet, but…", "Small catch:", "Heads up, I think…" |
| Unsure of your own read | own the doubt | "I might be reading this wrong, but…", "Could be me, but doesn't this…?" |
| Existing helper or pattern fits | suggestion question | "Does it make sense to use `formatDecimalValue` here?", "Could we reuse `X`?" |
| Missing test, or an edge case nobody handled | "should we" | "Should we also add a test for the empty body?", "Should we handle a template that was unpublished mid-update?" |

The register the user wants is "is this what you meant, or did it slip past?", asked very kindly. That idea can sit behind any of these openers; it does not need the word "intended".

### Voice

- Contractions always: it's, doesn't, I'd, we'd.
- "I think" is fine, once per comment. It is honest about what you can't know from the diff. Facts after it stay flat.
- One softener per comment, never stacked ("Not sure, but I think it might possibly" is three). "I think" counts as one. When the opener already softens ("I might be reading this wrong, but…"), drop the "I think".
- Plain verbs: "crashes", "never runs", "flips back to NLD", not "can lead to unexpected behaviour".
- "we" for the fix ("Could we…"), never "you should".

### Cut

- sentences that restate the diff; the author wrote it
- "why it matters" after the mechanism already showed it
- chains of "which… so… then"; one mechanism sentence
- "worth noting", "to be clear", "genuinely", "arguably", "I checked", "potential issue", "this ensures"
- em dashes, bold lead-ins, emoji, severity labels
- blame ("you forgot"), praise padding ("Nice work, but…")

### Before and after

Before, 440 characters, opener used on every comment in the review:

> Is it intended that `doc.check()` throws here during render? I think it crashes the inbox for any message with an empty body. `richTextJsonEmpty` has a `paragraph` with `content: []`, and `splitMessageContent` (`message-content.ts:25`) turns that into a paragraph inside a paragraph. Remirror rendered it fine. `check()` throws `Invalid content for node paragraph`, and only the `_app` boundary catches it.
>
> Would it work to add the fallback paragraph in `splitMessageContent` only when files were actually removed, and to catch here and fall back to an empty doc?

After, 230 characters:

> Not sure if you've hit this yet, but I think an empty message body crashes the inbox here. `splitMessageContent` (`message-content.ts:25`) nests a paragraph in a paragraph and `doc.check()` throws.
>
> Could we catch here and fall back to an empty doc?

A plausibly deliberate change keeps the intent question:

> Was skipping the reload after publish on purpose? The commit message says it reloads, but this only invalidates, so a dirty editor now relies on `reconcileQuestionnaireFormWithServer` alone.
>
> Would `router.reload()`, same as cancel, be safer?

### Read the batch, then humanize

1. Read all comments together, as the author will. No two open with the same three words. Intent phrasing ("intended", "on purpose", "did you mean") in at most one comment out of three. Vary the closing questions too ("Would…", "Could we…", "What about…", "Does it make sense to…").
2. Invoke `humanizer` and actually run its pass on the whole batch, even when the drafts already look clean. Tell it the register is a friendly teammate's PR comment, and that it must keep every backtick, `file:line`, symbol name and closing question, must not lengthen anything, and must not add jokes or flourishes. Use only its final text; its draft and audit passes stay out of the comments.
3. Hold the house rules after humanizing: every fix is a question, no blame, no emoji, no AI attribution anywhere.

## 5. Anchor and post as pending

Anchors, computed from the diff hunk headers:

- changed or added line: `side: "RIGHT"`, `line` = line number in the NEW file
- deleted file: `side: "LEFT"`, `line` = line number in the ORIGINAL file (whole file is in the diff, so any line works — pick the one that shows the problem)
- count new-file line numbers by walking the hunk from its `+start` value, skipping `-` lines

```bash
HEAD=$(gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha)
cat > $SCRATCH/review.json <<'JSON'
{
  "commit_id": "<HEAD>",
  "comments": [
    {"path": "...", "side": "RIGHT", "line": 26, "body": "..."}
  ]
}
JSON
```

Check the batch before posting. It flags comments over 400 characters, repeated three-word openers, em dashes, and intent questions in more than a third of the comments. Anything flagged goes back to section 4:

```bash
python3 <this skill's directory>/check_comments.py $SCRATCH/review.json
```

Then post:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews --method POST --input $SCRATCH/review.json \
  --jq '{id, state, url: .html_url}'
```

`state` must come back `PENDING`. Omitting `event` is what keeps it unsubmitted.

Verify the anchors landed:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id>/comments \
  --jq '.[]|{path, original_position, diff_hunk:(.diff_hunk[0:40])}'
```

`line` and `side` come back null on pending comments — that is normal. `original_position` and `diff_hunk` are what prove the comment sits where you meant.

## 5b. Approve when clean

When verification leaves zero red and zero yellow findings, approve the PR. Don't approve on a partial read: the source diff, the test diff and the commit list must all have been checked, and every scout must have reported back.

Skip the approval and report instead when any of these hold:
- the PR is a draft, or already merged or closed
- the PR author is the user (GitHub rejects self-approval)
- the user already has a pending review on it (GitHub allows one; it blocks a new review)

Approve with an empty body. No "LGTM" boilerplate, no summary, no attribution.

```bash
HEAD=$(gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha)
gh api repos/<owner>/<repo>/pulls/<n>/reviews --method POST \
  -f commit_id="$HEAD" -f event=APPROVE --jq '{id, state, url: .html_url}'
```

`state` must come back `APPROVED`.

## 6. Report

Use the `i-have-adhd` shape. On the clean path, first line: the review URL and that the PR is approved, then one line per check that cleared it, then any blue findings with an offer to post them as comments. Otherwise, first line: the review URL, and that it is pending, not submitted. Then one line per comment: `file:line` and what it asks. Findings left out get one line and an offer to add them. Last line: the one next action, usually "read them on GitHub and submit, or tell me which to cut".

## Gotchas

- `gh` keyring token can 401 while the git credential token works; if `gh api` fails, fall back to the REST API with the credential token.
- Body strings are JSON — use `\n\n` for paragraph breaks, not literal newlines inside a single-quoted heredoc value.
- One heredoc per review file, quoted (`<<'JSON'`) so backticks in comment bodies survive.
- Re-posting creates a second pending review. Add to the existing one with
  `gh api repos/<owner>/<repo>/pulls/<n>/comments` … or delete the old review first:
  `gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id> --method DELETE`.
- Re-read `.head.sha` just before posting. A force-push mid-review changes it, and a stale
  `commit_id` rejects the review. Diff the old head against the new one to see whether the
  content moved or it was only a rebase.
- `FETCH_HEAD` is clobbered by any later `git fetch`, including one a subagent runs. Pin the PR
  head to a real ref (`git update-ref refs/heads/pr<n> <sha>`) and hand subagents that name.
