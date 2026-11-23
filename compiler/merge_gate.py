#!/usr/bin/env python3
"""May this compiler PR merge without a human? (COMPILER.md step 9)

The rule, made mechanical. For every file the PR changes (from the merge base):
  - a new-knowledge surface (FREE_PREFIXES / FREE_FILES)   → free
  - an existing project card projects/<id>.md, modified    → free only if no line is
    deleted, every added line falls in a feed section (Known traps, Archive) and no
    existing line changes section (an injected `## ` heading would move them)
  - anything else (a new card, skills/, hooks/, compiler/, locked/, .github/ …) → human

The CI check (.github/workflows/brain-merge-gate.yml) runs the copy of this file
from the BASE branch, so a PR cannot loosen its own gate.

  python3 compiler/merge_gate.py --base origin/main [--head HEAD]
Exit: 0 may auto-merge · 1 needs a human · 2 git error
"""
import argparse
import difflib
import re
import subprocess
import sys

FREE_PREFIXES = ("incidents/", "runbooks/", "daily/", "policies/candidates/", "queue/")
FREE_FILES = {"projects/INDEX.md", "policies/CANDIDATES.md"}
# Sections the compiler feeds on a card: appending there needs no review.
FEED_SECTIONS = {"Known traps", "Archive"}

HEADING = re.compile(r"^## (?!#)(.+?)\s*$")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def _git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def is_free(path):
    return path in FREE_FILES or path.startswith(FREE_PREFIXES)


def is_project_card(path):
    if not (path.startswith("projects/") and path.endswith(".md")):
        return False
    return "/" not in path[len("projects/"):] and path != "projects/INDEX.md"


def section_map(text):
    """Line number (1-based) → name of the `## ` section the line is in.

    A heading belongs to its own section; everything before the first `## `
    (card title + field table) maps to None. `###` subheadings open no section.
    """
    out = [None]  # index 0 unused
    current = None
    for line in text.splitlines():
        m = HEADING.match(line)
        if m:
            current = m.group(1)
        out.append(current)
    return out


def line_allowed(section, line):
    """May this ADDED card line merge without a human?

    - title + field table (section None): nothing, not even a blank line — a blank
      line inside the table splits the markdown table;
    - feed sections: anything (bullets, ### subheadings, paragraphs, blank lines);
    - other sections (Owns, Depends on, Open debts …): only a blank line — appending
      `## Archive` at the end can drop a separator line into the section before it.
    """
    if section is None:
        return False
    if section in FEED_SECTIONS:
        return True
    return line.strip() == ""


def card_violations(diff, new_text):
    """Violations in one project card's `git diff -U0`."""
    sections = section_map(new_text)
    out = []
    lineno = None
    for line in diff.splitlines():
        m = HUNK.match(line)
        if m:
            lineno = int(m.group(1))
            continue
        if lineno is None or line.startswith("\\"):
            continue  # file header (---/+++) or "\ No newline at end of file"
        if line.startswith("-"):
            out.append(f"existing line deleted/changed: {line[1:][:80]!r}")
        elif line.startswith("+"):
            section = sections[lineno] if lineno < len(sections) else None
            if not line_allowed(section, line[1:]):
                where = f"'{section}' section" if section else "title/field table"
                out.append(f"line {lineno} added in the {where}: {line[1:][:80]!r}")
            lineno += 1
    return out


def moved_lines(old_text, new_text):
    """Unchanged card lines that now sit in a different `## ` section.

    Adding a heading moves the lines below it without deleting any: `## Archive`
    under the title would turn the field table into "archive", `## Known traps`
    inside Depends on would make its entries look like feedable traps.
    """
    old_lines, new_lines = old_text.splitlines(), new_text.splitlines()
    old_map, new_map = section_map(old_text), section_map(new_text)
    out = []
    matcher = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag != "equal":
            continue
        for k in range(i2 - i1):
            before, after = old_map[i1 + k + 1], new_map[j1 + k + 1]
            if before != after:
                out.append(f"line {j1 + k + 1} moved from '{before or 'title/field table'}' "
                           f"to '{after or 'title/field table'}' by a new heading: {new_lines[j1 + k][:80]!r}")
                break   # one per block is enough to gate the PR
    return out


def evaluate(base, head="HEAD"):
    """Violations of base...head (from the merge base); empty = may auto-merge."""
    rng = f"{base}...{head}"
    merge_base = _git("merge-base", base, head).strip()
    out = []
    for line in _git("diff", "--name-status", "-M", rng).splitlines():
        status, *paths = line.split("\t")
        if all(is_free(p) for p in paths):
            continue
        path = paths[-1]
        if is_project_card(path) and status == "M":
            diff = _git("diff", "-U0", rng, "--", path)
            new = _git("show", f"{head}:{path}")
            old = _git("show", f"{merge_base}:{path}")
            out += [f"{path}: {v}" for v in card_violations(diff, new) + moved_lines(old, new)]
        else:
            out.append(f"{path}: outside the auto-merge surface (status {status})")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", required=True, help="e.g. origin/main")
    ap.add_argument("--head", default="HEAD")
    a = ap.parse_args(argv)
    try:
        violations = evaluate(a.base, a.head)
    except subprocess.CalledProcessError as e:
        print(f"git error: {' '.join(e.cmd)}\n{e.stderr}", file=sys.stderr)
        return 2
    if violations:
        print("NEEDS A HUMAN — changes outside the auto-merge surface:")
        for v in violations:
            print(f"  - {v}")
        return 1
    print("May auto-merge: new-knowledge surfaces and card feeds only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
