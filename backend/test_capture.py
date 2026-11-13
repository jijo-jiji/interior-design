"""How a wall was measured on its photo travels with the design.

The sales app sends the four corners it was marked by (fractions of the
photo), the photo's size and lens, and how the phone was held. The server
keeps them, clean, on the project: to check a design against a tape later,
and as labelled photos for a learned corner finder.

Run from the repo root:  python -m pytest backend/test_capture.py
"""

import os
import sys

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import main  # noqa: E402

CAPTURE = {
    "method": "corners",
    "corners": [[0.11, 0.08], [0.93, 0.12], [0.9, 0.95], [0.08, 0.9]],
    "photo_px": [1920, 1080],
    "focal_px": 1555.0,
    "photo_aspect": 1.4812,
    "focal_source": "photo",
    "tilt_deg": {"roll": -0.8, "pitch": 3.1},
}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    monkeypatch.setattr(main, "PLAN_DIR", str(tmp_path / "plan_images"))
    monkeypatch.setattr(main, "PICTURE_DIR", str(tmp_path / "design_pictures"))
    monkeypatch.setattr(main, "WALL_PHOTO_DIR", str(tmp_path / "wall_photos"))
    return TestClient(main.app)


def _quote(client, capture, quote_id="QT-CAPTEST"):
    resp = client.post("/quote", json={
        "quote_id": quote_id,
        "wall": {"width_mm": 4000, "height_mm": 2700, "depth_mm": 150},
        "obstacles": [{"type": "window", "distance_from_left_mm": 1500,
                       "distance_from_floor_mm": 1000, "width_mm": 1200,
                       "height_mm": 1000}],
        "capture": capture,
    })
    assert resp.status_code == 200, resp.text
    return client.get(f"/api/projects/{quote_id}").json()


def test_the_measurement_is_kept_with_the_project(client):
    project = _quote(client, CAPTURE)
    assert project["capture"] == CAPTURE


def test_junk_is_dropped_and_the_rest_kept(client):
    project = _quote(client, {
        **CAPTURE,
        "photo_px": ["1920", 1080],  # not numbers
        "focal_source": "guessed",  # not a known source
        "tilt_deg": {"roll": True, "pitch": 3},  # a bool is not an angle
        "extra": "x" * 1000,  # not a field
    })
    capture = project["capture"]
    assert "photo_px" not in capture
    assert "focal_source" not in capture
    assert "tilt_deg" not in capture
    assert "extra" not in capture
    assert capture["corners"] == CAPTURE["corners"]
    assert capture["focal_px"] == CAPTURE["focal_px"]


@pytest.mark.parametrize("corners", [
    None,
    [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9]],  # three corners
    [[0.1, 0.1], [0.9, 0.1], [1.4, 0.9], [0.1, 0.9]],  # off the photo
    [[0.1, 0.1], [0.9, 0.1], [0.9, "0.9"], [0.1, 0.9]],  # a string
])
def test_without_four_sensible_corners_nothing_is_kept(client, corners):
    project = _quote(client, {**CAPTURE, "corners": corners})
    assert "capture" not in project


def test_the_suggested_corners_are_kept_beside_the_confirmed(client):
    suggested = [[0.12, 0.09], [0.92, 0.12], [0.9, 0.94], [0.08, 0.9]]
    project = _quote(client, {**CAPTURE, "suggested_corners": suggested})
    assert project["capture"]["suggested_corners"] == suggested
    assert project["capture"]["corners"] == CAPTURE["corners"]
    # Junk suggestions are dropped; the rest stays.
    project = _quote(client, {**CAPTURE, "suggested_corners": [[2, 0], [1, 0]]}, quote_id="QT-CAPJUNK")
    assert "suggested_corners" not in project["capture"]
    assert project["capture"]["corners"] == CAPTURE["corners"]


def test_the_hidden_wall_bottom_is_kept_if_sensible(client):
    bottom = [[0.86, 0.62], [0.3, 0.6]]
    project = _quote(client, {**CAPTURE, "wall_bottom": bottom}, quote_id="QT-CAPWB")
    assert project["capture"]["wall_bottom"] == bottom
    for junk in ([[0.86, 0.62]], [[0.86, 0.62], [0.3, 2.0]], "x"):
        project = _quote(client, {**CAPTURE, "wall_bottom": junk}, quote_id="QT-CAPWBJ")
        assert "wall_bottom" not in project["capture"]


def test_where_the_size_came_from_is_kept_if_known(client):
    project = _quote(client, {**CAPTURE, "size_from": "worktop"}, quote_id="QT-CAPSF")
    assert project["capture"]["size_from"] == "worktop"
    project = _quote(client, {**CAPTURE, "size_from": "a guess"}, quote_id="QT-CAPSF2")
    assert "size_from" not in project["capture"]


def test_how_the_suggestion_was_found_is_kept_if_known(client):
    suggested = [[0.12, 0.09], [0.92, 0.12], [0.9, 0.94], [0.08, 0.9]]
    project = _quote(client, {**CAPTURE, "suggested_corners": suggested, "suggested_by": "learned"})
    assert project["capture"]["suggested_by"] == "learned"
    project = _quote(client, {**CAPTURE, "suggested_corners": suggested, "suggested_by": "x" * 5000},
                     quote_id="QT-CAPBY")
    assert "suggested_by" not in project["capture"]
    # Without the corners it describes, it's dropped.
    project = _quote(client, {**CAPTURE, "suggested_by": "planes"}, quote_id="QT-CAPBY2")
    assert "suggested_by" not in project["capture"]


def test_a_design_without_one_has_none(client):
    project = _quote(client, None)
    assert "capture" not in project


# ── The wall photo ───────────────────────────────────────────────────────────

def _phone_photo() -> bytes:
    """A JPEG as a phone writes it: stored sideways with an EXIF rotation,
    and a GPS position (the client's home)."""
    import io
    from PIL import Image

    photo = Image.new("RGB", (60, 40), (200, 190, 180))
    photo.putpixel((0, 0), (255, 0, 0))  # top-left, before rotating
    exif = Image.Exif()
    exif[0x0112] = 6  # Orientation: rotate 90° clockwise to show
    exif.get_ifd(0x8825)[2] = (3.0, 8.0, 50.0)  # GPSLatitude
    buf = io.BytesIO()
    photo.save(buf, "JPEG", exif=exif.tobytes())
    return buf.getvalue()


def _with_photo(client, quote_id="QT-PHOTOTEST", **extra):
    import base64

    url = "data:image/jpeg;base64," + base64.b64encode(_phone_photo()).decode()
    body = {
        "quote_id": quote_id,
        "wall": {"width_mm": 4000, "height_mm": 2700, "depth_mm": 150},
        "capture": CAPTURE,
        "wall_photo": url,
        **extra,
    }
    resp = client.post("/quote", json=body)
    assert resp.status_code == 200, resp.text
    return client.get(f"/api/projects/{quote_id}").json()


def test_the_photo_is_kept_upright_and_without_its_location(client):
    from PIL import Image

    project = _with_photo(client)
    assert project["capture"]["photo_kept"] is True
    path = main._wall_photo_path("QT-PHOTOTEST")
    with Image.open(path) as kept:
        # Turned as the app showed it: 40 wide, 60 tall.
        assert kept.size == (40, 60)
        exif = kept.getexif()
        assert 0x8825 not in exif and not exif.get_ifd(0x8825)  # no GPS
        assert 0x0112 not in exif  # nothing left to rotate


def test_the_photo_is_never_served(client):
    _with_photo(client)
    for route in ("wall.jpg", "wall_photo", "photo.jpg"):
        assert client.get(f"/api/projects/QT-PHOTOTEST/{route}").status_code == 404
    # Nor is it in the database.
    with open(main.DB_PATH, encoding="utf-8") as f:
        assert "base64" not in f.read()


def test_the_client_can_say_no(client):
    _with_photo(client)
    assert os.path.exists(main._wall_photo_path("QT-PHOTOTEST"))
    # Sent again with the switch off: the copy kept before is removed.
    project = _with_photo(client, keep_wall_photo=False)
    assert not os.path.exists(main._wall_photo_path("QT-PHOTOTEST"))
    assert "photo_kept" not in project["capture"]


def test_no_photo_without_corners(client):
    project = _with_photo(client, capture=None)
    assert "capture" not in project
    assert not os.path.exists(main._wall_photo_path("QT-PHOTOTEST"))


def test_not_a_photo_is_not_kept(client):
    import base64

    resp = client.post("/quote", json={
        "quote_id": "QT-PHOTOJUNK",
        "wall": {"width_mm": 4000, "height_mm": 2700, "depth_mm": 150},
        "capture": CAPTURE,
        "wall_photo": "data:image/jpeg;base64," + base64.b64encode(b"not a jpeg").decode(),
    })
    assert resp.status_code == 200
    assert not os.path.exists(main._wall_photo_path("QT-PHOTOJUNK"))


def test_the_quote_tells_the_client(client, monkeypatch):
    seen = {}
    real = main._generate_pdf

    def spy(**kwargs):
        seen["kept"] = kwargs.get("wall_photo_kept")
        return real(**kwargs)

    monkeypatch.setattr(main, "_generate_pdf", spy)
    _with_photo(client)
    assert seen["kept"] is True
    _with_photo(client, quote_id="QT-PHOTONONE", keep_wall_photo=False)
    assert seen["kept"] is False
