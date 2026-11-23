"""Tests for kit/update.py. Run: python3 -m unittest tests/test_update.py

`install.sh update` replaces the kit's own (engine) files with a newer release and
must never touch the team's files: cards, dailies, locked decisions, brain.conf,
their README. A repo made from the template shares no git history with the kit,
so the manifest is the only thing that says which file belongs to whom.
"""
import os
import stat
import subprocess
import sys
import tempfile
import unittest

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(KIT, "kit"))
import manifest  # noqa: E402
import update  # noqa: E402


def write(root, path, text, mode=None):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(text)
    if mode:
        os.chmod(full, mode)


def read(root, path):
    with open(os.path.join(root, path), encoding="utf-8") as f:
        return f.read()


def release(files, version):
    """A downloaded kit release: engine files + kit/VERSION + kit.manifest."""
    src = tempfile.mkdtemp()
    files = dict(files, **{"kit/VERSION": version + "\n"})
    for p, t in files.items():
        write(src, p, t)
    write(src, "kit.manifest", manifest.render(manifest.build(src, list(files))))
    return src


def installed(files, version):
    """A team's brain installed from `files` at `version`, plus the team's own content."""
    root = tempfile.mkdtemp()
    files = dict(files, **{"kit/VERSION": version + "\n"})
    for p, t in files.items():
        write(root, p, t)
    m = manifest.render(manifest.build(root, list(files)))
    write(root, "kit.manifest", m)
    write(root, ".brain-kit/manifest", m)
    write(root, ".brain-kit/version", version + "\n")
    write(root, "daily/2026-11-01-zeynep-aaaa1111.md", "team daily\n")
    write(root, "projects/INDEX.md", "| id |\n")
    write(root, "README.md", "Our brain — we rewrote this README.\n")
    write(root, "brain.conf", "NAME=Atlas\n")
    return root


def snapshot(root):
    out = {}
    for d, subdirs, files in os.walk(root):
        subdirs[:] = [s for s in subdirs if s != ".brain-kit"]
        for f in files:
            p = os.path.relpath(os.path.join(d, f), root)
            out[p] = manifest.sha256_file(os.path.join(root, p))
    return out


def run_main(root, src, *flags):
    return update.main(["--root", root, "--source", src, *flags])


class MakePlan(unittest.TestCase):
    def test_plan_add_change_remove(self):
        root = installed({"a": "a\n", "b": "b\n"}, "0.1.0")
        old = manifest.parse(read(root, ".brain-kit/manifest"))
        src = release({"b": "b2\n", "c": "c\n"}, "0.2.0")
        new = manifest.parse(read(src, "kit.manifest"))
        p = update.make_plan(root, old, new)
        self.assertEqual(p.add, ["c"])
        self.assertEqual(p.change, ["b", "kit/VERSION"])
        self.assertEqual(p.remove, ["a"])
        self.assertEqual(p.conflicts, [])

    def test_conflict_locally_edited(self):
        root = installed({"a": "a\n"}, "0.1.0")
        write(root, "a", "edited by the team\n")
        old = manifest.parse(read(root, ".brain-kit/manifest"))
        new = manifest.parse(read(release({"a": "a2\n"}, "0.2.0"), "kit.manifest"))
        self.assertEqual(update.make_plan(root, old, new).conflicts, ["a"])

    def test_edited_but_untouched_is_not_a_conflict(self):
        root = installed({"a": "a\n", "b": "b\n"}, "0.1.0")
        write(root, "a", "edited by the team\n")
        old = manifest.parse(read(root, ".brain-kit/manifest"))
        new = manifest.parse(read(release({"a": "a\n", "b": "b2\n"}, "0.2.0"), "kit.manifest"))
        p = update.make_plan(root, old, new)
        self.assertEqual(p.conflicts, [])
        self.assertNotIn("a", p.change)

    def test_conflict_new_path_collides(self):
        root = installed({"a": "a\n"}, "0.1.0")
        write(root, "d", "the team's own file\n")
        old = manifest.parse(read(root, ".brain-kit/manifest"))
        new = manifest.parse(read(release({"a": "a\n", "d": "kit d\n"}, "0.2.0"), "kit.manifest"))
        p = update.make_plan(root, old, new)
        self.assertEqual(p.blocked, ["d"])        # a TEAM file in the way, not a local edit
        self.assertEqual(p.conflicts, [])
        write(root, "d", "kit d\n")
        p = update.make_plan(root, old, new)
        self.assertEqual((p.conflicts, p.blocked), ([], []))
        self.assertNotIn("d", p.add)

    def test_deleted_engine_file_is_restored(self):
        root = installed({"a": "a\n"}, "0.1.0")
        os.remove(os.path.join(root, "a"))
        old = manifest.parse(read(root, ".brain-kit/manifest"))
        new = manifest.parse(read(release({"a": "a\n"}, "0.2.0"), "kit.manifest"))
        self.assertIn("a", update.make_plan(root, old, new).change)


class BadPaths(unittest.TestCase):
    def test_bad_paths(self):
        root = tempfile.mkdtemp()
        bad = ["/etc/x", "../x", "hooks/../../x", "daily/x.md", "projects/INDEX.md", "locked/d.md",
               "README.md", "brain.conf", ".git/config", ".brain-kit/manifest", ""]
        try:
            os.symlink(tempfile.mkdtemp(), os.path.join(root, "out"))
            bad.append("out/x")
        except OSError:
            pass  # Windows without symlink privilege
        self.assertEqual(sorted(update.bad_paths(root, bad + ["hooks/a.sh", "docs/kit/x.md"])), sorted(bad))


class Main(unittest.TestCase):
    def test_updates_and_records_state(self):
        root = installed({"hooks/a.sh": "a\n", "old.sh": "o\n"}, "0.1.0")
        src = release({"hooks/a.sh": "a2\n", "new.sh": "n\n"}, "0.2.0")
        self.assertEqual(run_main(root, src, "--yes"), 0)
        self.assertEqual(read(root, "hooks/a.sh"), "a2\n")
        self.assertEqual(read(root, "new.sh"), "n\n")
        self.assertFalse(os.path.exists(os.path.join(root, "old.sh")))
        self.assertEqual(read(root, ".brain-kit/version"), "0.2.0\n")
        self.assertEqual(read(root, ".brain-kit/manifest"), read(src, "kit.manifest"))
        self.assertEqual(read(root, "kit.manifest"), read(src, "kit.manifest"))

    def test_already_up_to_date(self):
        files = {"hooks/a.sh": "a\n"}
        root = installed(files, "0.1.0")
        before = snapshot(root)
        self.assertEqual(run_main(root, release(files, "0.1.0"), "--yes"), 0)
        self.assertEqual(snapshot(root), before)

    def test_content_untouched(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        team = {p: h for p, h in snapshot(root).items()
                if p.startswith(("daily/", "projects/")) or p in ("README.md", "brain.conf")}
        self.assertEqual(run_main(root, release({"hooks/a.sh": "a2\n"}, "0.2.0"), "--yes"), 0)
        after = snapshot(root)
        self.assertEqual({p: after[p] for p in team}, team)

    def test_main_refuses_protected_in_manifest(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        before = snapshot(root)
        src = release({"hooks/a.sh": "a2\n", "projects/INDEX.md": "kit index\n"}, "0.2.0")
        self.assertEqual(run_main(root, src, "--yes"), 1)
        self.assertEqual(snapshot(root), before)

    def test_main_conflict_exit3_then_force_backs_up(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        write(root, "hooks/a.sh", "team edit\n")
        src = release({"hooks/a.sh": "a2\n"}, "0.2.0")
        self.assertEqual(run_main(root, src, "--yes"), 3)
        self.assertEqual(read(root, "hooks/a.sh"), "team edit\n")
        self.assertEqual(run_main(root, src, "--yes", "--force"), 0)
        self.assertEqual(read(root, "hooks/a.sh"), "a2\n")
        backups = os.listdir(os.path.join(root, ".brain-kit", "backup"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(read(root, os.path.join(".brain-kit", "backup", backups[0], "hooks/a.sh")), "team edit\n")

    def test_force_never_overwrites_a_team_file(self):
        # the kit never touches team files: --force backs up and overwrites LOCAL EDITS of engine files,
        # never a team file that happens to sit where a new release adds one.
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        write(root, "docs/kit/notes.md", "the team's own notes\n")
        src = release({"hooks/a.sh": "a\n", "docs/kit/notes.md": "kit notes\n"}, "0.2.0")
        self.assertEqual(run_main(root, src, "--yes", "--force"), 3)
        self.assertEqual(read(root, "docs/kit/notes.md"), "the team's own notes\n")

    def test_changelog_between(self):
        log = ("# Changelog\n\n## 0.3.0 — x\n\n- three\n\n## 0.2.0 — y\n\n- two\n"
               "\n## 0.1.0 — z\n\n- one\n")
        out = update.changelog_between(log, "0.1.0", "0.3.0")
        self.assertIn("- three", out)
        self.assertIn("- two", out)
        self.assertNotIn("- one", out)
        self.assertEqual(update.changelog_between(log, "0.3.0", "0.3.0"), "")

    def test_preview_shows_changelog(self):
        root = installed({"a.sh": "a\n"}, "0.1.0")
        src = release({"a.sh": "a2\n"}, "0.2.0")
        write(src, "CHANGELOG.md", "# Changelog\n\n## 0.2.0 — d\n\n- MANUAL STEP: rename x\n\n## 0.1.0 — d\n\n- first\n")
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", src, "--yes"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("MANUAL STEP: rename x", r.stdout)
        self.assertNotIn("- first", r.stdout)

    @unittest.skipIf(os.name == "nt", "Windows has no exec bit; Git Bash runs scripts via bash")
    def test_apply_keeps_exec_bit(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        src = release({"hooks/a.sh": "a2\n", "hooks/b.sh": "b\n"}, "0.2.0")
        os.chmod(os.path.join(src, "hooks/a.sh"), 0o755)
        os.chmod(os.path.join(src, "hooks/b.sh"), 0o755)
        self.assertEqual(run_main(root, src, "--yes"), 0)
        for p in ("hooks/a.sh", "hooks/b.sh"):
            self.assertTrue(os.stat(os.path.join(root, p)).st_mode & stat.S_IXUSR, p)

    def test_removed_dir_is_cleaned_up(self):
        root = installed({"hooks/a.sh": "a\n", "gone/deep/x.sh": "x\n"}, "0.1.0")
        self.assertEqual(run_main(root, release({"hooks/a.sh": "a\n"}, "0.2.0"), "--yes"), 0)
        self.assertFalse(os.path.exists(os.path.join(root, "gone")))

    def test_verify_source_detects_tamper(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        before = snapshot(root)
        src = release({"hooks/a.sh": "a2\n"}, "0.2.0")
        write(src, "hooks/a.sh", "tampered\n")
        self.assertEqual(update.verify_source(src, manifest.parse(read(src, "kit.manifest"))), ["changed: hooks/a.sh"])
        self.assertEqual(run_main(root, src, "--yes"), 1)
        self.assertEqual(snapshot(root), before)

    def test_missing_state_asks_for_init(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        os.remove(os.path.join(root, ".brain-kit", "manifest"))
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", release({"hooks/a.sh": "a2\n"}, "0.2.0"), "--yes"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("install.sh init", r.stdout + r.stderr)

    def test_no_tty_without_yes_aborts(self):
        root = installed({"hooks/a.sh": "a\n"}, "0.1.0")
        before = snapshot(root)
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", release({"hooks/a.sh": "a2\n"}, "0.2.0")],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertEqual(snapshot(root), before)

    @unittest.skipIf(os.name == "nt", "no pty module on Windows")
    def test_terminal_eof_at_prompt_is_not_confirmed(self):
        # Windows reports the NUL device as a tty; there, and on a terminal where the
        # user presses Ctrl-D, the prompt hits EOF — that is "no", never a crash.
        import pty
        root = installed({"a.sh": "a\n"}, "0.1.0")
        before = snapshot(root)
        master, slave = pty.openpty()
        os.write(master, b"\x04")
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", release({"a.sh": "a2\n"}, "0.2.0")],
                           stdin=slave, capture_output=True, text=True, timeout=30)
        os.close(slave)
        os.close(master)
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertEqual(snapshot(root), before)

    def test_non_utf8_console_does_not_crash(self):
        # Windows: Python's console is cp1252; the preview prints "→".
        root = installed({"a.sh": "a\n"}, "0.1.0")
        env = dict(os.environ, PYTHONIOENCODING="cp1252")
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", release({"a.sh": "a2\n"}, "0.2.0"), "--yes"],
                           capture_output=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(read(root, "a.sh"), "a2\n")

    def test_preview_lists_changes(self):
        root = installed({"a.sh": "a\n", "b.sh": "b\n"}, "0.1.0")
        r = subprocess.run([sys.executable, os.path.join(KIT, "kit", "update.py"), "--root", root,
                            "--source", release({"a.sh": "a2\n", "c.sh": "c\n"}, "0.2.0"), "--yes"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        for line in ("+ c.sh", "~ a.sh", "- b.sh"):
            self.assertIn(line, r.stdout)


if __name__ == "__main__":
    unittest.main()
