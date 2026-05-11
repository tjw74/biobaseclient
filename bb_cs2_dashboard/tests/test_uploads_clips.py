"""Unit tests for clip upload listing helpers (no DB; filesystem is source of truth)."""

from __future__ import annotations

import os
import tempfile
import time
import unittest
from pathlib import Path

from fastapi import HTTPException


class ClipUploadHelpersTests(unittest.TestCase):
    def test_clip_display_name_strips_uuid_prefix(self) -> None:
        from app import _clip_display_name

        key32 = "a" * 32
        self.assertEqual(_clip_display_name(f"{key32}_my.demo"), "my.demo")

    def test_clip_display_name_unknown_passthrough(self) -> None:
        from app import _clip_display_name

        self.assertEqual(_clip_display_name("manual_drop.bin"), "manual_drop.bin")

    def test_resolve_stored_clip_file_ok(self) -> None:
        from app import _resolve_stored_clip_file

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        (tmp / "abc.bin").write_bytes(b"!")
        p = _resolve_stored_clip_file("abc.bin", root=tmp)
        self.assertEqual(p.name, "abc.bin")

    def test_resolve_stored_clip_rejects_subpath_style_name(self) -> None:
        from app import _resolve_stored_clip_file

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        (tmp / "only.txt").write_bytes(b"x")
        with self.assertRaises(HTTPException) as ctx:
            _resolve_stored_clip_file("nested/only.txt", root=tmp)
        self.assertEqual(ctx.exception.status_code, 400)

    def test_list_clip_uploads_sorts_newest_first(self) -> None:
        from app import _list_clip_uploads

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        old = tmp / "b_old.txt"
        new = tmp / "a_new.txt"
        old.write_text("o")
        new.write_text("n")

        ts = time.time() - 3600
        os.utime(old, (ts, ts))

        rows = _list_clip_uploads(root=tmp)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["name"], "a_new.txt")


if __name__ == "__main__":
    unittest.main()
