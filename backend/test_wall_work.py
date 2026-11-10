"""Work on the wall itself: a hidden door, a door or a window cut into a
solid wall, and a finish over it (paint, tiles, panels), priced from the
catalogue's wall_work (sample prices until the designer's are in).

Run from the repo root:  python -m pytest backend/test_wall_work.py
"""

import os
import shutil
import subprocess
import sys

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import catalog as catalog_lib  # noqa: E402
from backend import main  # noqa: E402

HIDDEN_DOOR = {"type": "door", "distance_from_left_mm": 2600, "distance_from_floor_mm": 0,
               "width_mm": 800, "height_mm": 2100, "work": "hidden_door"}
OLD_WINDOW = {"type": "window", "distance_from_left_mm": 1200, "distance_from_floor_mm": 1000,
              "width_mm": 1200, "height_mm": 1100}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    return TestClient(main.app)


def _send(client, **extra):
    body = {
        "quote_id": "QT-WALL-1",
        "wall": {"width_mm": 3600, "height_mm": 2700, "depth_mm": 150},
        "obstacles": [OLD_WINDOW, HIDDEN_DOOR],
        "placed_cabinets": [{"cabinet_type": "base_600", "label": "Base 600", "width_mm": 600,
                             "height_mm": 850, "depth_mm": 600, "x_mm": -1500}],
        "style_archetype": "japandi",
        "client_name": "Encik Hafiz",
        "wall_finish": {"kind": "tiles", "area_m2": 6.254, "colour": "#D9D4CC", "junk": 1},
    }
    body.update(extra)
    response = client.post("/quote", json=body)
    assert response.status_code in (200, 201), response.text
    return response.json()


def test_the_quote_has_a_line_for_each_kind_of_wall_work(client):
    quote = _send(client)
    lines = {li["description"]: li for li in quote["line_items"]}
    door = lines["Wall work — Hidden door, flush with the wall"]
    assert (door["qty"], door["unit_price"], door["total"]) == (1, 2400, 2400)
    tiles = lines["Wall finish — Wall tiles, supplied and laid (6.25 m² @ RM140/m²)"]
    assert tiles["total"] == 875.0
    # The window that is already there costs nothing to make.
    assert not any("New window" in d for d in lines)


def test_the_record_keeps_what_is_to_be_made_and_the_finish(client):
    _send(client)
    record = client.get("/api/projects/QT-WALL-1").json()
    assert [o.get("work") for o in record["obstacles"]] == [None, "hidden_door"]
    assert record["wall_finish"] == {"kind": "tiles", "area_m2": 6.25, "colour": "#d9d4cc"}


def test_a_studio_save_can_change_or_clear_the_finish(client):
    _send(client)
    client.put("/api/projects/QT-WALL-1", json={"wall_finish": {"kind": "paint", "area_m2": 9}})
    assert client.get("/api/projects/QT-WALL-1").json()["wall_finish"] == {"kind": "paint", "area_m2": 9.0}
    client.put("/api/projects/QT-WALL-1", json={"wall_finish": None})
    assert client.get("/api/projects/QT-WALL-1").json().get("wall_finish") is None


@pytest.mark.parametrize("raw", [
    None, "tiles", {"kind": ""}, {"kind": "tiles"}, {"kind": "tiles", "area_m2": 0},
    {"kind": "tiles", "area_m2": -3}, {"kind": "tiles", "area_m2": "lots"}, {"kind": 5, "area_m2": 2},
    {"kind": "tiles", "area_m2": 5000},
])
def test_a_finish_that_makes_no_sense_is_dropped(raw):
    assert main._clean_wall_finish(raw) is None


def test_the_served_catalogue_lists_the_wall_work(client):
    doc = client.get("/api/catalog").json()
    work = doc["wall_work"]
    assert work["is_placeholder"] is True
    assert set(work["openings"]) == {"hidden_door", "door", "window"}
    assert set(work["finishes"]) == {"paint", "tiles", "panels"}


def test_a_catalogue_saved_before_wall_work_gets_the_samples():
    doc = catalog_lib.default_catalog().model_dump(mode="json")
    del doc["wall_work"]
    old = catalog_lib.Catalog.model_validate(doc)
    assert old.wall_work.openings["hidden_door"].price == 2400


def test_a_misspelt_wall_work_key_is_refused():
    doc = catalog_lib.default_catalog().model_dump(mode="json")
    doc["wall_work"]["openings"]["door"]["prise"] = 1
    with pytest.raises(Exception):
        catalog_lib.Catalog.model_validate(doc)


@pytest.mark.skipif(shutil.which("pdftotext") is None, reason="needs pdftotext")
def test_the_pdf_lists_the_wall_work(client):
    _send(client)
    pdf = client.get("/pdf/QT-WALL-1")
    assert pdf.status_code == 200
    text = subprocess.run(["pdftotext", "-layout", "-", "-"], input=pdf.content,
                          capture_output=True, check=True).stdout.decode()
    assert "Hidden door, flush with the wall" in text
    assert "6.25 m² @ RM140/m²" in text
