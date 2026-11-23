"""Tests for compiler/merge_gate.py. Run: python3 -m unittest tests/test_merge_gate.py

The gate decides whether a compiler PR may merge without a human. It passes when
the PR only touches new-knowledge surfaces and, on project cards, only appends under
`## Known traps` / `## Archive`. Anything that touches hand-set fields (the field
table, aliases, Owns, Depends on, Open debts), deletes a line or opens a new card
waits for a human. Why: in the reference brain the gate used to hold every card
feed for review; nobody ever changed one, and the single-open-PR rule meant the
held PR blocked the queue (25 → 105 candidates in one week).
"""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "compiler"))
import merge_gate  # noqa: E402

CARD = """# billing-api

| field | value |
|---|---|
| `id` | `billing-api` |
| `aliases` | billing, invoices |

## Owns

Issues invoices.

## Depends on

- Redis

## Known traps

- first trap

## Open debts

- a debt

## Archive

- 2026-09 event
"""


def git(*args):
    subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], check=True, capture_output=True, text=True)


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def commit(msg="change"):
    git("add", "-A")
    git("commit", "-q", "-m", msg)


class MergeGateTest(unittest.TestCase):
    """Each test runs in a temp repo: CARD on main, the change on `compiler/test`."""

    def setUp(self):
        self.old_cwd = os.getcwd()
        self.repo = tempfile.mkdtemp()
        os.chdir(self.repo)
        git("init", "-q", "-b", "main")
        git("config", "user.email", "ci@local")
        git("config", "user.name", "ci")
        write("projects/billing-api.md", CARD)
        write("projects/INDEX.md", "| id |\n|---|\n| billing-api |\n")
        write("daily/2026-10-01-zeynep-aaaa1111.md", "summary\n")
        commit("seed")
        git("switch", "-q", "-c", "compiler/test")

    def tearDown(self):
        os.chdir(self.old_cwd)

    def edit_card(self, old, new):
        text = read("projects/billing-api.md")
        self.assertIn(old, text)
        write("projects/billing-api.md", text.replace(old, new, 1))

    def violations(self):
        commit()
        return merge_gate.evaluate("main", "HEAD")

    # --- may auto-merge ------------------------------------------------------

    def test_known_traps_append_ok(self):
        self.edit_card("- first trap\n", "- first trap\n- new trap (daily x)\n")
        self.assertEqual(self.violations(), [])

    def test_archive_append_at_end_ok(self):
        write("projects/billing-api.md", CARD + "- 2026-11 event (daily y)\n")
        self.assertEqual(self.violations(), [])

    def test_new_knowledge_surfaces_ok(self):
        write("incidents/index-stale-2026-11.md", "# outage\n")
        write("runbooks/rotate-keys.md", "# rotate\n")
        write("queue/candidates.md", "queue\n")
        write("policies/candidates/p1.md", "policy\n")
        write("policies/CANDIDATES.md", "| id |\n")
        write("projects/INDEX.md", "| id |\n|---|\n| billing-api |\n| new |\n")
        os.makedirs("daily/archive/2026-10")
        git("mv", "daily/2026-10-01-zeynep-aaaa1111.md", "daily/archive/2026-10/")
        self.assertEqual(self.violations(), [])

    def test_archive_subheading_and_paragraph_ok(self):
        write("projects/billing-api.md", CARD + "\n### 2026-11 run\n\nA plain paragraph.\n")
        self.assertEqual(self.violations(), [])

    def test_blank_line_in_other_section_ok(self):
        self.edit_card("Issues invoices.\n", "Issues invoices.\n\n")
        self.assertEqual(self.violations(), [])

    def test_after_merging_main_only_the_branch_counts(self):
        # a human changes Owns on main; the branch merges main, then feeds the card
        git("switch", "-q", "main")
        self.edit_card("Issues invoices.\n", "Issues invoices; fixed by a human.\n")
        commit("cards: human fix")
        git("switch", "-q", "compiler/test")
        git("merge", "-q", "--no-edit", "main")
        self.edit_card("- first trap\n", "- first trap\n- new trap\n")
        self.assertEqual(self.violations(), [])

    # --- waits for a human ---------------------------------------------------

    def test_owns_append_gated(self):
        self.edit_card("Issues invoices.\n", "Issues invoices.\nAnd something else.\n")
        v = self.violations()
        self.assertEqual(len(v), 1)
        self.assertIn("'Owns' section", v[0])

    def test_alias_change_gated(self):
        self.edit_card("billing, invoices |", "billing, invoices, payments |")
        v = self.violations()
        self.assertTrue(any("deleted/changed" in i for i in v), v)

    def test_field_table_row_gated(self):
        self.edit_card("| `aliases` | billing, invoices |\n", "| `aliases` | billing, invoices |\n| `status` | active |\n")
        v = self.violations()
        self.assertEqual(len(v), 1)
        self.assertIn("field table", v[0])

    def test_blank_line_in_field_table_gated(self):
        # a blank line inside the table splits the markdown table in two
        self.edit_card("|---|---|\n", "|---|---|\n\n")
        v = self.violations()
        self.assertEqual(len(v), 1)
        self.assertIn("field table", v[0])

    def test_known_traps_delete_gated(self):
        self.edit_card("- first trap\n", "")
        v = self.violations()
        self.assertTrue(any("deleted/changed" in i for i in v), v)

    def test_new_card_gated(self):
        write("projects/new-card.md", "# new-card\n\n## Known traps\n\n- x\n")
        v = self.violations()
        self.assertEqual(len(v), 1)
        self.assertIn("projects/new-card.md", v[0])

    def test_gated_surface(self):
        write("skills/brain-routing/SKILL.md", "changed\n")
        v = self.violations()
        self.assertEqual(len(v), 1)
        self.assertIn("outside the auto-merge surface", v[0])

    def test_customers_not_free(self):
        # an unknown top-level directory is not an auto-merge surface
        write("customers/acme.md", "# acme\n")
        self.assertEqual(len(self.violations()), 1)

    def test_locked_not_free(self):
        write("locked/decisions.md", "changed\n")
        self.assertEqual(len(self.violations()), 1)

    def test_compiler_and_gate_not_free(self):
        write("compiler/merge_gate.py", "# loosened\n")
        write(".github/workflows/brain-merge-gate.yml", "x\n")
        self.assertEqual(len(self.violations()), 2)

    def test_heading_injected_under_title_gated(self):
        # "## Archive" above the field table moves the hand-set fields into a feed section
        self.edit_card("# billing-api\n", "# billing-api\n\n## Archive\n")
        v = self.violations()
        self.assertTrue(v, "heading injection must not auto-merge")

    def test_heading_injected_inside_section_gated(self):
        self.edit_card("## Depends on\n\n- Redis\n", "## Depends on\n\n## Known traps\n- Redis\n")
        self.assertTrue(self.violations())

    def test_archive_section_appended_at_end_ok(self):
        text = CARD.split("## Archive")[0].rstrip("\n") + "\n"
        write("projects/billing-api.md", text); commit("no archive yet")
        git("switch", "-q", "main"); git("merge", "-q", "--no-ff", "--no-edit", "compiler/test")
        git("switch", "-q", "compiler/test")
        write("projects/billing-api.md", text + "\n## Archive\n\n- 2026-11 event\n")
        self.assertEqual(self.violations(), [])

    # --- CLI -----------------------------------------------------------------

    def test_cli_exit_codes(self):
        self.edit_card("- first trap\n", "- first trap\n- new trap\n")
        commit()
        self.assertEqual(merge_gate.main(["--base", "main"]), 0)
        self.edit_card("Issues invoices.\n", "Something else.\n")
        commit()
        self.assertEqual(merge_gate.main(["--base", "main"]), 1)
        self.assertEqual(merge_gate.main(["--base", "no-such-ref"]), 2)


class SectionMapTest(unittest.TestCase):
    def test_heading_belongs_to_its_section_table_is_none(self):
        m = merge_gate.section_map(CARD)
        lines = CARD.splitlines()
        self.assertIsNone(m[lines.index("| `aliases` | billing, invoices |") + 1])
        self.assertEqual(m[lines.index("## Known traps") + 1], "Known traps")
        self.assertEqual(m[lines.index("- first trap") + 1], "Known traps")
        self.assertEqual(m[len(lines)], "Archive")

    def test_subheading_does_not_open_a_section(self):
        self.assertEqual(merge_gate.section_map("## Archive\n\n### 2026-11\n- x\n")[4], "Archive")


if __name__ == "__main__":
    unittest.main()
