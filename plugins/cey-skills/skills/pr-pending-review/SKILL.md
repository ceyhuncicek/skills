---
name: pr-pending-review
description: Use when given a GitHub PR link or number and asked to review it - runs an Opus-delegated investigation, ranks findings, and leaves them as PENDING (unsubmitted) inline review comments on GitHub in a soft, question-framed tone.
---

# pr-pending-review

Input: a PR URL or number. Output: a pending GitHub review the user submits themselves, plus a terse chat summary.

Never submit the review. Never approve or request changes. `event` is always omitted from the API call.

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

Run the drafts through the `humanizer` skill before posting. Then apply the house tone:

- open with a question: "Is this intended?", "Was dropping the file intended, or did it just stop compiling?"
- propose the fix as a question: "Would returning null here be safer?", "Worth gating on `isInitialLoading`?"
- no blame, no "you forgot", no severity emoji, no praise padding
- 1-3 short paragraphs, blank line between them
- name symbols and line numbers so the author can jump straight there
- no AI attribution anywhere

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

## 6. Report

Give the user the review URL, state plainly that it is not submitted, and list what each comment says in one line. Offer to append findings that were left out.

## Gotchas

- `gh` keyring token can 401 while the git credential token works; if `gh api` fails, fall back to the REST API with the credential token.
- Body strings are JSON — use `\n\n` for paragraph breaks, not literal newlines inside a single-quoted heredoc value.
- One heredoc per review file, quoted (`<<'JSON'`) so backticks in comment bodies survive.
- Re-posting creates a second pending review. Add to the existing one with
  `gh api repos/<owner>/<repo>/pulls/<n>/comments` … or delete the old review first:
  `gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id> --method DELETE`.
