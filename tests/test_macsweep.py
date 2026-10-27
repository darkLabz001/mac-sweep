import os
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from macsweep import Candidate, human_size, move_to_trash, scan


class MacSweepTests(unittest.TestCase):
    def test_scan_finds_only_old_regular_files(self):
        with TemporaryDirectory() as directory:
            tmp_path = Path(directory)
            cache = tmp_path / "Library" / "Caches" / "demo"
            cache.mkdir(parents=True)
            old_file = cache / "old.bin"
            old_file.write_bytes(b"x" * 2048)
            new_file = cache / "new.bin"
            new_file.write_bytes(b"new")
            old_time = time.time() - 40 * 86400
            os.utime(old_file, (old_time, old_time))

            found = scan(tmp_path, {"caches"}, 30)

            self.assertEqual([item.path for item in found], [old_file])
            self.assertEqual(found[0].size, 2048)

    def test_move_to_trash_avoids_collisions(self):
        with TemporaryDirectory() as directory:
            tmp_path = Path(directory)
            source = tmp_path / "Downloads" / "report.txt"
            source.parent.mkdir()
            source.write_text("new")
            trash = tmp_path / ".Trash"
            trash.mkdir()
            (trash / "report.txt").write_text("existing")

            move_to_trash(Candidate(source, "downloads", source.stat().st_size, source.stat().st_mtime), tmp_path)

            self.assertFalse(source.exists())
            self.assertEqual((trash / "report (1).txt").read_text(), "new")

    def test_human_size(self):
        self.assertEqual(human_size(1024 * 1024), "1.0 MB")
