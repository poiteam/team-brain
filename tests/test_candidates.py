"""Tests for compiler/candidates.py. Run: python3 -m unittest tests/test_candidates.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "compiler"))
import candidates  # noqa: E402

ENTRY = """# secret-in-diff
- policy: Secrets (`.env*`, storage keys, database passwords) never enter a diff or a transcript.
- artifact: hook (pre-commit scan) — the brain's scan-secrets pattern applied to project repos
- scope: cross-repo (brain is source of truth)
- seen: 3
- status: candidate
- evidence:
  - daily a — 2026-01-12 — one
  - daily b — 2026-01-19 — two
"""


def entry(id_, status="candidate", seen=1, policy="short policy"):
    return {"id": id_, "status": status, "seen": seen, "artifact": "hook", "policy": policy, "evidence": 1}


class ReadEntry(unittest.TestCase):
    def test_fields_are_parsed(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "secret-in-diff.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(ENTRY)
        e = candidates.read_entry(path)
        self.assertEqual(e["id"], "secret-in-diff")
        self.assertEqual(e["status"], "candidate")
        self.assertEqual(e["seen"], 3)
        self.assertEqual(e["artifact"], "hook")          # first word only
        self.assertEqual(e["evidence"], 2)
        self.assertTrue(e["policy"].startswith("Secrets (`.env*`"))

    def test_heading_must_match_file_name(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "other-id.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(ENTRY)
        with self.assertRaises(ValueError):
            candidates.read_entry(path)


class Ordering(unittest.TestCase):
    def test_triage_order(self):
        # triage first (awaiting a decision), then candidates by seen desc, then closed ones.
        es = [
            entry("z-rej", status="rejected:not needed", seen=9),
            entry("b-cand", seen=2),
            entry("a-cand", seen=2),
            entry("c-cand", seen=5),
            entry("appr", status="approved→hooks/x.sh", seen=8),
            entry("tri", status="triage", seen=1),
        ]
        self.assertEqual([x["id"] for x in candidates.ordered(es)],
                         ["tri", "c-cand", "a-cand", "b-cand", "appr", "z-rej"])


class Table(unittest.TestCase):
    def test_policy_is_cut_at_a_word_boundary_and_pipes_are_escaped(self):
        long = "word " * 40 + "a|b"
        row = candidates.table([entry("x", policy=long)]).splitlines()[-1]
        self.assertIn("[x](candidates/x.md)", row)
        self.assertIn(" …", row)
        self.assertNotIn("wor …", row)                   # no half words
        self.assertEqual(row.count("|"), 6)              # 5 columns, no raw | in content

    def test_only_the_marked_block_changes(self):
        md = "intro\n<!-- CANDIDATES:BEGIN -->\nold\n<!-- CANDIDATES:END -->\noutro\n"
        self.assertEqual(candidates.write_index(md, "TABLE"),
                         "intro\n<!-- CANDIDATES:BEGIN -->\nTABLE\n<!-- CANDIDATES:END -->\noutro\n")

    def test_missing_markers_is_an_error(self):
        with self.assertRaises(ValueError):
            candidates.write_index("no markers\n", "TABLE")


class Check(unittest.TestCase):
    def test_stale_index_is_detected(self):
        root = tempfile.mkdtemp()
        os.makedirs(os.path.join(root, "policies", "candidates"))
        with open(os.path.join(root, "policies", "candidates", "secret-in-diff.md"), "w", encoding="utf-8") as f:
            f.write(ENTRY)
        index = os.path.join(root, "policies", "CANDIDATES.md")
        with open(index, "w", encoding="utf-8") as f:
            f.write("x\n<!-- CANDIDATES:BEGIN -->\n<!-- CANDIDATES:END -->\n")
        self.assertFalse(candidates.is_current(root))
        candidates.generate(root)
        self.assertTrue(candidates.is_current(root))
        with open(index, encoding="utf-8") as f:
            self.assertIn("secret-in-diff", f.read())


if __name__ == "__main__":
    unittest.main()
