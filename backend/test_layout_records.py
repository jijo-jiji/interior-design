"""A layout keeps its shape through the office server.

The sales app's generator stores each cabinet's kind, wall (main / side) and
mounting height. The server used to drop them on the way in (quote) and on
the way out (project list), so a generated L-shape came back broken in both
the studio and the sales app.

Run from the repo root:  python -m pytest backend/test_layout_records.py
"""

import os
import sys

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import main  # noqa: E402

GENERATED = [
    {"id": "B-01", "cabinet_type": "corner_900", "label": "Corner 900", "kind": "corner", "run": "main",
     "width_mm": 900, "height_mm": 850, "depth_mm": 900, "mount_mm": 0, "x_mm": -1050, "generated": True},
    {"id": "B-02", "cabinet_type": "base_hob_600", "label": "Hob 600", "kind": "hob", "run": "main",
     "width_mm": 600, "height_mm": 850, "depth_mm": 600, "mount_mm": 0, "x_mm": 150, "generated": True},
    {"id": "B-03", "cabinet_type": "wall_450", "label": "Wall 450", "kind": "wall", "run": "main",
     "width_mm": 450, "height_mm": 700, "depth_mm": 320, "mount_mm": 1400, "x_mm": -375, "generated": True},
    {"id": "B-04", "cabinet_type": "base_sink_800", "label": "Sink 800", "kind": "sink", "run": "return",
     "width_mm": 800, "height_mm": 850, "depth_mm": 600, "mount_mm": 0, "offset_mm": 1300, "generated": True},
]


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    return TestClient(main.app)


def _send_quote(client):
    response = client.post("/quote", json={
        "quote_id": "QT-LAYOUT-1",
        "wall": {"width_mm": 3000, "height_mm": 2700, "depth_mm": 150, "shape": "lShape", "return_mm": 2400},
        "obstacles": [],
        "placed_cabinets": GENERATED,
        "style_archetype": "japandi",
        "client_name": "Puan Aminah",
    })
    assert response.status_code in (200, 201), response.text
    return client.get("/api/projects/QT-LAYOUT-1").json()


def test_a_sent_quote_keeps_the_generated_layout(client):
    project = _send_quote(client)
    for stored in (project["placed_cabinets"], project["cabinets"]):
        by_id = {c["id"]: c for c in stored}
        assert by_id["B-02"]["kind"] == "hob"
        assert by_id["B-03"]["mount_mm"] == 1400
        assert by_id["B-04"]["run"] == "return"
        assert by_id["B-04"]["offset_mm"] == 1300
        assert all(c["generated"] for c in stored)


def test_studio_positions_use_the_real_wall_width(client):
    cabs = {c["id"]: c for c in _send_quote(client)["cabinets"]}
    # Corner: centre 1050 mm left of a 3 m wall's centre → left edge at 0.
    assert cabs["B-01"]["x"] == pytest.approx(0.0)
    # Hob: centre 150 mm right of centre → left edge 1.35 m.
    assert cabs["B-02"]["x"] == pytest.approx(1.35)
    # Every wall unit hangs, not just the 600.
    assert cabs["B-03"]["isWallMounted"] is True
    # The sales app's own convention is untouched.
    assert cabs["B-02"]["x_mm"] == 150


def test_a_studio_save_reads_back_unchanged(client):
    _send_quote(client)
    saved = {
        "id": "S-1", "cabinet_type": "base_600", "type": "base_600", "kind": "base", "run": "main",
        "x": 0.9, "width": 0.6, "height": 0.85, "depth": 0.6, "width_mm": 600, "height_mm": 850,
        "depth_mm": 600, "mount_mm": 0, "x_mm": -300,
    }
    assert client.put("/api/projects/QT-LAYOUT-1", json={"cabinets": [saved]}).status_code == 200
    cab = client.get("/api/projects/QT-LAYOUT-1").json()["cabinets"][0]
    assert cab["x"] == pytest.approx(0.9)
    assert cab["x_mm"] == -300
