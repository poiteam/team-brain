"""Tests for kit/manifest.py. Run: python3 -m unittest tests/test_manifest.py

kit.manifest lists every engine file of a release with its sha256. `install.sh update`
compares it with the working tree, so one format and one hash function serve both the
release build and the update — a mismatch would make every file look locally edited.
"""
import os
import subprocess
import sys
import tempfile
import unittest

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(KIT, "kit"))
import manifest  # noqa: E402


def tree(files):
    root = tempfile.mkdtemp()
    for path, data in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)
    return root


class Manifest(unittest.TestCase):
    def test_roundtrip(self):
        entries = {"hooks/a.sh": "a" * 64, "compiler/b.py": "b" * 64}
        self.assertEqual(manifest.parse(manifest.render(entries)), entries)

    def test_sorted(self):
        text = manifest.render({"z.sh": "1" * 64, "a.sh": "2" * 64})
        self.assertEqual(text, f"{'2' * 64}  a.sh\n{'1' * 64}  z.sh\n")

    def test_parse_rejects_bad_line(self):
        for bad in ("nothash  a.sh\n", f"{'a' * 64} a.sh\n", f"{'a' * 64}  \n"):
            with self.assertRaises(ValueError, msg=bad):
                manifest.parse(bad)

    def test_parse_ignores_blank_lines(self):
        self.assertEqual(manifest.parse(f"\n{'a' * 64}  x\n\n"), {"x": "a" * 64})

    def test_crlf_same_hash(self):
        root = tree({"lf.sh": b"echo a\necho b\n", "crlf.sh": b"echo a\r\necho b\r\n"})
        self.assertEqual(manifest.sha256_file(os.path.join(root, "lf.sh")),
                         manifest.sha256_file(os.path.join(root, "crlf.sh")))

    def test_different_content_different_hash(self):
        root = tree({"a": b"x\n", "b": b"y\n"})
        self.assertNotEqual(manifest.sha256_file(os.path.join(root, "a")),
                            manifest.sha256_file(os.path.join(root, "b")))

    def test_build(self):
        root = tree({"hooks/a.sh": b"a\n", "b.md": b"b\n"})
        m = manifest.build(root, ["hooks/a.sh", "b.md"])
        self.assertEqual(set(m), {"hooks/a.sh", "b.md"})
        self.assertEqual(m["b.md"], manifest.sha256_file(os.path.join(root, "b.md")))


class Cli(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, os.path.join(KIT, "kit", "manifest.py"), *args],
                              capture_output=True, text=True)

    def test_cli_build(self):
        root = tree({"hooks/a.sh": b"a\n", "b.md": b"b\n"})
        r = self.run_cli("build", "--root", root, "b.md", "hooks/a.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(manifest.parse(r.stdout), manifest.build(root, ["b.md", "hooks/a.sh"]))

    def test_cli_check(self):
        root = tree({"hooks/a.sh": b"a\n", "b.md": b"b\n"})
        path = os.path.join(root, "kit.manifest")
        with open(path, "w") as f:
            f.write(manifest.render(manifest.build(root, ["hooks/a.sh", "b.md"])))
        r = self.run_cli("check", "--root", root, path)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(os.path.join(root, "b.md"), "w") as f:
            f.write("changed\n")
        r = self.run_cli("check", "--root", root, path)
        self.assertEqual(r.returncode, 1)
        self.assertIn("b.md", r.stdout + r.stderr)

    def test_cli_check_missing_file(self):
        root = tree({"a": b"a\n"})
        path = os.path.join(root, "kit.manifest")
        with open(path, "w") as f:
            f.write(manifest.render({"a": manifest.sha256_file(os.path.join(root, "a")), "gone": "0" * 64}))
        r = self.run_cli("check", "--root", root, path)
        self.assertEqual(r.returncode, 1)
        self.assertIn("gone", r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
