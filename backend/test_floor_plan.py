"""A floor plan travels with its design through the office server.

The sales app sends the plan a room was read from (the picture as a data URL,
plus walls and rooms in mm) with the quote. The server stores the picture as
a file, keeps the geometry on the project, and serves the picture back for
the Studio's and the sales app's Room and House views.

Run from the repo root:  python -m pytest backend/test_floor_plan.py
"""

import base64
import io
import json
import os
import sys

import pytest
from fastapi.testclient import TestClient
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import main  # noqa: E402


def _png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (40, 30), "white").save(buf, format="PNG")
    return buf.getvalue()


PLAN = {
    "image_center_mm": [4000, 2500],
    "image_size_mm": [10000, 7000],
    "image_rotation_deg": 0,
    "kitchen_mm": [0, 0, 3000, 2400],
    "wall_thickness_mm": 150,
    "walls": [[-150, -150, 3300, 150]],
    "rooms": [{"name": "DAPUR", "rect_mm": [0, 0, 3000, 2400]}],
}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    monkeypatch.setattr(main, "PLAN_DIR", str(tmp_path / "plan_images"))
    return TestClient(main.app)


def _quote(client, plan, quote_id="QT-PLANTEST"):
    resp = client.post("/quote", json={
        "quote_id": quote_id,
        "wall": {"width_mm": 3000, "height_mm": 2700, "depth_mm": 150,
                 "shape": "lShape", "return_mm": 2400},
        "floor_plan": plan,
    })
    assert resp.status_code == 200, resp.text
    return resp.json()["quote_id"]


def test_the_picture_is_stored_as_a_file_and_served(client):
    png = _png()
    quote_id = _quote(client, {**PLAN, "image": "data:image/png;base64," + base64.b64encode(png).decode()})

    project = client.get(f"/api/projects/{quote_id}").json()
    plan = project["floor_plan"]
    assert plan["image"] == f"/api/projects/{quote_id}/plan.png"
    assert plan["walls"] == PLAN["walls"]
    assert plan["rooms"][0]["name"] == "DAPUR"

    picture = client.get(plan["image"])
    assert picture.status_code == 200
    assert picture.headers["content-type"] == "image/png"
    assert picture.content == png

    # The database holds the address, not hundreds of KB of picture.
    with open(main.DB_PATH, encoding="utf-8") as f:
        assert "base64" not in f.read()


def test_a_design_sent_again_keeps_its_stored_picture(client):
    stored = {**PLAN, "image": "/api/projects/QT-PLANTEST/plan.png"}
    quote_id = _quote(client, stored)
    assert client.get(f"/api/projects/{quote_id}").json()["floor_plan"]["image"] == stored["image"]


def test_something_that_is_not_a_png_is_dropped(client):
    junk = "data:image/png;base64," + base64.b64encode(b"not a picture").decode()
    quote_id = _quote(client, {**PLAN, "image": junk})
    plan = client.get(f"/api/projects/{quote_id}").json()["floor_plan"]
    assert "image" not in plan
    assert plan["kitchen_mm"] == PLAN["kitchen_mm"]  # the geometry is kept


def test_no_plan_no_change(client):
    resp = client.post("/quote", json={
        "quote_id": "QT-NOPLAN",
        "wall": {"width_mm": 4000, "height_mm": 2700, "depth_mm": 150},
    })
    assert resp.status_code == 200
    assert "floor_plan" not in client.get("/api/projects/QT-NOPLAN").json()


def test_the_picture_address_cannot_reach_other_files(client):
    assert client.get("/api/projects/..%2Fprojects_db/plan.png").status_code == 404
    assert client.get("/api/projects/QT-NONE/plan.png").status_code == 404
