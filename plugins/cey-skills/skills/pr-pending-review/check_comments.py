"""Pre-post check for a pending review payload.

Usage: python3 check_comments.py <review.json>

Flags comments over the 400-char cap, comments that open with the same three
words as an earlier one, em dashes, and too many intent questions.
Exit code 1 when anything is flagged.
"""

import json
import re
import sys

comments = json.load(open(sys.argv[1]))["comments"]
seen = set()
intent = 0
flagged = False

for c in comments:
    body = c["body"]
    opener = " ".join(re.sub(r"[^\w\s]", "", body).lower().split()[:3])
    flags = []
    if len(body) > 400:
        flags.append("OVER")
    if opener in seen:
        flags.append("SAME-OPENER")
    if "—" in body:
        flags.append("EMDASH")
    if re.search(r"intend|on purpose|did you mean", body, re.I):
        intent += 1
    seen.add(opener)
    flagged |= bool(flags)
    where = f"{c['path'].split('/')[-1]}:{c.get('line')}"
    print(f"{len(body):4d}  {where:40} [{opener}] {' '.join(flags)}")

limit = max(1, len(comments) // 3)
if intent > limit:
    flagged = True
    print(f"TOO MANY INTENT QUESTIONS: {intent}/{len(comments)} (max {limit})")

sys.exit(1 if flagged else 0)
