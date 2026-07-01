from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient


class DemoNativeApiTests(unittest.TestCase):
    def test_get_and_create_demo_labels(self) -> None:
        import app as app_mod

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        parsed_dir = tmp / "parsed-demos"
        labels_dir = tmp / "labels"
        parsed_dir.mkdir(parents=True)
        demo_id = "a" * 24
        (parsed_dir / f"{demo_id}.json").write_text(
            json.dumps(
                {
                    "demoId": demo_id,
                    "mapName": "de_mirage",
                    "tickRateGuess": 64,
                    "startTick": 10,
                    "endTick": 100,
                    "frames": [],
                    "events": [],
                }
            )
        )

        with (
            patch.object(app_mod, "DASHBOARD_TOKEN", ""),
            patch.object(app_mod, "DEMO_PLAYER_PARSED_DIR", parsed_dir),
            patch.object(app_mod, "DEMO_PLAYER_LABELS_DIR", labels_dir),
        ):
            client = TestClient(app_mod.dashboard)
            demo = client.get(f"/api/demos/{demo_id}")
            self.assertEqual(demo.status_code, 200, demo.text)
            self.assertEqual(demo.json()["mapName"], "de_mirage")

            labels = client.get(f"/api/demos/{demo_id}/labels")
            self.assertEqual(labels.status_code, 200, labels.text)
            self.assertEqual(labels.json(), [])

            created = client.post(
                f"/api/demos/{demo_id}/labels",
                json={
                    "startTick": 42,
                    "endTick": 64,
                    "title": "late rotate",
                    "note": "arrived after contact",
                    "tags": ["rotate", "timing"],
                },
            )
            self.assertEqual(created.status_code, 200, created.text)
            body = created.json()
            self.assertEqual(body["demoId"], demo_id)
            self.assertEqual(body["startTick"], 42)
            self.assertEqual(body["endTick"], 64)
            self.assertEqual(body["title"], "late rotate")

            labels_after = client.get(f"/api/demos/{demo_id}/labels")
            self.assertEqual(labels_after.status_code, 200, labels_after.text)
            self.assertEqual(len(labels_after.json()), 1)

    def test_upload_parses_and_returns_summary_contract(self) -> None:
        import app as app_mod
        import demo_native

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        upload_dir = tmp / "uploads"
        parsed_dir = tmp / "parsed-demos"
        parsed_payload = {
            "demoId": "b" * 24,
            "mapName": "de_inferno",
            "tickRateGuess": 64,
            "startTick": 1,
            "endTick": 128,
            "frames": [{"tick": 1, "timeSec": 0, "players": []}],
            "events": [],
        }

        def fake_parse_and_save(demo_path: Path, output_dir: Path, *, source_filename: str | None = None):
            output_dir.mkdir(parents=True, exist_ok=True)
            out = output_dir / f"{parsed_payload['demoId']}.json"
            out.write_text(json.dumps(parsed_payload))
            return parsed_payload, out

        with (
            patch.object(app_mod, "DASHBOARD_TOKEN", ""),
            patch.object(app_mod, "DEMO_PLAYER_UPLOAD_DIR", upload_dir),
            patch.object(app_mod, "DEMO_PLAYER_PARSED_DIR", parsed_dir),
            patch.object(demo_native, "parse_and_save_demo", side_effect=fake_parse_and_save),
        ):
            client = TestClient(app_mod.dashboard)
            response = client.post(
                "/api/demos/upload",
                files={"demo": ("match.dem", b"x" * 4096, "application/octet-stream")},
            )

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertTrue(body["ok"])
        self.assertEqual(body["demoId"], parsed_payload["demoId"])
        self.assertEqual(body["mapName"], "de_inferno")
        self.assertEqual(body["frameCount"], 1)
        self.assertTrue(upload_dir.is_dir())


if __name__ == "__main__":
    unittest.main()
