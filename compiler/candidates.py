#!/usr/bin/env python3
"""Policy-candidate queue table — policies/candidates/*.md → policies/CANDIDATES.md.

Each candidate lives in its own file (policies/candidates/<id>.md). The table in
CANDIDATES.md is a PROJECTION: never edited by hand, this script regenerates it.
The compiler runs it after touching any candidate; CI runs --check.

Why one file per entry: entries are FED over time (seen +1, a new evidence line)
and must be found by id; a single queue file grows past what an agent can read
in one go (the reference brain's reached 106 KB with 109 entries).

Usage:
  python3 compiler/candidates.py           # regenerate the table
  python3 compiler/candidates.py --check   # exit 1 if the table is stale
"""
import argparse
import os
import re
import sys

BEGIN = "<!-- CANDIDATES:BEGIN -->"
END = "<!-- CANDIDATES:END -->"

# Triage order: awaiting a decision first, then the queue, closed ones last.
_STATUS_ORDER = {"triage": 0, "candidate": 1, "approved": 2, "rejected": 3}
POLICY_WIDTH = 110


def _field(text, name):
    m = re.search(rf"(?m)^- {name}:[ \t]*(.*)$", text)
    return m.group(1).strip() if m else ""


def read_entry(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    id_ = os.path.basename(path)[:-3]
    m = re.match(r"# (\S+)\s*\n", text)
    if not m or m.group(1) != id_:
        raise ValueError(f"{path}: heading must be '# {id_}' (found: {m.group(1) if m else 'none'})")
    evidence = text.split("\n- evidence:", 1)[1] if "\n- evidence:" in text else ""
    seen = _field(text, "seen")
    return {
        "id": id_,
        "policy": _field(text, "policy"),
        "artifact": (_field(text, "artifact").split() or ["?"])[0],
        "status": _field(text, "status"),
        "seen": int(seen) if seen.isdigit() else 0,
        "evidence": len(re.findall(r"(?m)^  - ", evidence)),
    }


def _status_root(status):
    return re.split(r"[→:]", status, maxsplit=1)[0].strip()


def ordered(entries):
    return sorted(entries, key=lambda e: (_STATUS_ORDER.get(_status_root(e["status"]), 9), -e["seen"], e["id"]))


def _shorten(text, width=POLICY_WIDTH):
    text = text.replace("|", "/")
    if len(text) <= width:
        return text
    cut = text[:width]
    if " " in cut:
        cut = cut[: cut.rindex(" ")]
    return cut + " …"


def table(entries):
    rows = ["| id | status | seen | artifact | policy |", "|---|---|---|---|---|"]
    for e in ordered(entries):
        rows.append(
            f"| [{e['id']}](candidates/{e['id']}.md) | {e['status'].replace('|', '/')} | {e['seen']} "
            f"| {e['artifact']} | {_shorten(e['policy'])} |"
        )
    return "\n".join(rows)


def write_index(md, table_text):
    if BEGIN not in md or END not in md:
        raise ValueError(f"CANDIDATES.md is missing the {BEGIN} / {END} markers")
    before, rest = md.split(BEGIN, 1)
    _, after = rest.split(END, 1)
    return f"{before}{BEGIN}\n{table_text}\n{END}{after}"


def _paths(root):
    return os.path.join(root, "policies", "candidates"), os.path.join(root, "policies", "CANDIDATES.md")


def _target(root):
    directory, index = _paths(root)
    entries = [read_entry(os.path.join(directory, n)) for n in sorted(os.listdir(directory)) if n.endswith(".md")]
    with open(index, encoding="utf-8") as f:
        current = f.read()
    return current, write_index(current, table(entries))


def is_current(root):
    current, target = _target(root)
    return current == target


def generate(root):
    _, target = _target(root)
    with open(_paths(root)[1], "w", encoding="utf-8") as f:
        f.write(target)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--root", default=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
    p.add_argument("--check", action="store_true", help="exit 1 if the table is stale; write nothing")
    a = p.parse_args(argv)
    if a.check:
        if is_current(a.root):
            print("policies/CANDIDATES.md is current")
            return 0
        print("policies/CANDIDATES.md is STALE — run 'python3 compiler/candidates.py'", file=sys.stderr)
        return 1
    generate(a.root)
    print("policies/CANDIDATES.md regenerated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
