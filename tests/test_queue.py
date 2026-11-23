"""Tests for compiler/queue.py. Run: python3 -m unittest tests/test_queue.py

Backlog mode: candidates the size gate cannot fit are NOT dropped; they are
written in full to queue/candidates.md and the next run applies them before new
ones. (Reference brain, first backlog run: the gate left 77 of 152 candidates
behind and the watermark moved past their dailies — they would never have come back.)
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "compiler"))
import queue_candidates as q  # noqa: E402

BLOCK = """CANDIDATE: card-feed
TARGET: billing-api
BODY: retries are not idempotent.
SOURCE: 2026-09-22-zeynep-aaaa1111.md
ADDED: 2026-09-27
"""


def brain(body, dailies=("daily/archive/2026-09/2026-09-22-zeynep-aaaa1111.md",)):
    k = tempfile.mkdtemp()
    for d in dailies:
        os.makedirs(os.path.join(k, os.path.dirname(d)), exist_ok=True)
        open(os.path.join(k, d), "w").close()
    os.makedirs(os.path.join(k, "queue"))
    with open(os.path.join(k, "queue", "candidates.md"), "w", encoding="utf-8") as f:
        f.write(f"# Candidate queue\n\n{q.BEGIN}\n{body}{q.END}\n")
    return k


class Parse(unittest.TestCase):
    def test_blocks_are_parsed(self):
        b = q.read(brain(BLOCK + "\n" + BLOCK.replace("billing-api", "web-app")))
        self.assertEqual([x["TARGET"] for x in b], ["billing-api", "web-app"])
        self.assertEqual(b[0]["ADDED"], "2026-09-27")

    def test_empty_queue_is_valid(self):
        k = brain("")
        self.assertEqual(q.read(k), [])
        self.assertEqual(q.check(k), [])


class Check(unittest.TestCase):
    def test_valid_queue(self):
        self.assertEqual(q.check(brain(BLOCK)), [])

    def test_invalid_type(self):
        self.assertTrue(any("CANDIDATE" in e for e in q.check(brain(BLOCK.replace("card-feed", "card-feed|billing-api")))))

    def test_missing_field(self):
        self.assertTrue(any("ADDED" in e for e in q.check(brain(BLOCK.replace("ADDED: 2026-09-27\n", "")))))

    def test_source_daily_must_exist_archive_included(self):
        self.assertEqual(q.check(brain(BLOCK)), [])
        self.assertTrue(any("SOURCE" in e for e in q.check(brain(BLOCK.replace("aaaa1111", "ffffffff")))))

    def test_duplicate_block(self):
        self.assertTrue(any("duplicate" in e for e in q.check(brain(BLOCK + "\n" + BLOCK))))

    def test_markers_required(self):
        k = brain(BLOCK)
        with open(os.path.join(k, "queue", "candidates.md"), "w", encoding="utf-8") as f:
            f.write("no markers\n")
        self.assertTrue(q.check(k))


class Summary(unittest.TestCase):
    def test_count_oldest_stale(self):
        old = BLOCK.replace("2026-09-27", "2026-09-10").replace("billing-api", "web-app")
        s = q.summary(brain(BLOCK + "\n" + old), today="2026-09-27")
        self.assertEqual((s["count"], s["oldest"], s["stale"]), (2, "2026-09-10", 1))


if __name__ == "__main__":
    unittest.main()
