#!/usr/bin/env python3
"""Candidate queue — backlog mode (COMPILER.md steps 1, 2, 3, 5).

Candidates the size gate (step 5) cannot fit are NOT dropped: they are written
in full to queue/candidates.md, and the next run applies them BEFORE new ones.
Why: the watermark moves past a run's dailies, so a dropped candidate is never
scanned again — in the reference brain's first backlog run the gate left 77 of
152 candidates behind.

Block format = summarize.sh output plus the date it entered the queue:

    CANDIDATE: <card-feed|new-card|alias|locked-change|policy-candidate>
    TARGET: <id>
    BODY: <one paragraph>
    SOURCE: <daily file name>
    ADDED: <YYYY-MM-DD>     # KEPT when a block is carried over again

(Named queue_candidates, not queue: a module called "queue" would shadow Python's own.)

Usage:
  python3 compiler/queue_candidates.py --check     # exit 1 on a malformed queue (CI)
  python3 compiler/queue_candidates.py --summary   # "N candidates · oldest <date> · stale K"
"""
import argparse
import datetime
import os
import re
import sys

BEGIN = "<!-- QUEUE:BEGIN -->"
END = "<!-- QUEUE:END -->"
FIELDS = ("CANDIDATE", "TARGET", "BODY", "SOURCE", "ADDED")
TYPES = {"card-feed", "new-card", "alias", "locked-change", "policy-candidate"}
STALE_DAYS = 7


def _path(root):
    return os.path.join(root, "queue", "candidates.md")


def _body(root):
    with open(_path(root), encoding="utf-8") as f:
        text = f.read()
    if BEGIN not in text or END not in text:
        raise ValueError(f"queue/candidates.md is missing the {BEGIN} / {END} markers")
    return text.split(BEGIN, 1)[1].split(END, 1)[0]


def read(root):
    blocks = []
    for raw in re.split(r"\n\s*\n", _body(root).strip()):
        if not raw.strip():
            continue
        b = {}
        for line in raw.strip().splitlines():
            m = re.match(r"^([A-Z]+):\s?(.*)$", line)
            if m and m.group(1) in FIELDS and m.group(1) not in b:
                b[m.group(1)] = m.group(2).strip()
            else:
                b.setdefault("_extra", []).append(line)
        blocks.append(b)
    return blocks


def _daily_exists(root, name):
    if os.path.exists(os.path.join(root, "daily", name)):
        return True
    m = re.match(r"(\d{4}-\d{2})-", name)
    return bool(m) and os.path.exists(os.path.join(root, "daily", "archive", m.group(1), name))


def check(root):
    try:
        blocks = read(root)
    except (OSError, ValueError) as e:
        return [str(e)]
    errors, seen = [], set()
    for i, b in enumerate(blocks, 1):
        where = f"block {i} ({b.get('TARGET', '?')})"
        for field in FIELDS:
            if not b.get(field):
                errors.append(f"{where}: no {field} field")
        if b.get("_extra"):
            errors.append(f"{where}: unrecognised line: {b['_extra'][0][:60]}")
        if b.get("CANDIDATE") and b["CANDIDATE"] not in TYPES:
            errors.append(f"{where}: invalid CANDIDATE type '{b['CANDIDATE']}' (the CANDIDATE line carries only the type)")
        if b.get("SOURCE") and not _daily_exists(root, b["SOURCE"]):
            errors.append(f"{where}: SOURCE daily not found: {b['SOURCE']}")
        if b.get("ADDED") and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", b["ADDED"]):
            errors.append(f"{where}: ADDED is not a date: {b['ADDED']}")
        key = (b.get("CANDIDATE"), b.get("TARGET"), b.get("BODY"), b.get("SOURCE"))
        if key in seen:
            errors.append(f"{where}: duplicate block")
        seen.add(key)
    return errors


def summary(root, today=None):
    blocks = read(root)
    today = datetime.date.fromisoformat(today) if today else datetime.date.today()
    dates = sorted(b["ADDED"] for b in blocks if re.fullmatch(r"\d{4}-\d{2}-\d{2}", b.get("ADDED", "")))
    cutoff = (today - datetime.timedelta(days=STALE_DAYS)).isoformat()
    return {"count": len(blocks), "oldest": dates[0] if dates else None, "stale": sum(1 for d in dates if d < cutoff)}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--root", default=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--summary", action="store_true")
    a = p.parse_args(argv)
    if a.check:
        errors = check(a.root)
        for e in errors:
            print(f"queue: {e}", file=sys.stderr)
        if not errors:
            print(f"queue/candidates.md is valid ({len(read(a.root))} candidates)")
        return 1 if errors else 0
    s = summary(a.root)
    print(f"{s['count']} candidates · oldest {s['oldest'] or '-'} · older than {STALE_DAYS} days {s['stale']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
