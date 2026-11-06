"""Pictures of the design travel with the quote.

The sales app sends pictures of the 3D design with the quote (data URLs). The
server stores them as files, prints them in the quote PDF, and serves them to
the client on a page they open from the message.

Run from the repo root:  python -m pytest backend/test_pictures.py
"""

import base64
import io
import os
import sys

import pytest
from fastapi.testclient import TestClient
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import main  # noqa: E402


def _image(fmt: str = "JPEG", size=(160, 100), colour="#c9a24f") -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, colour).save(buf, format=fmt)
    return buf.getvalue()


def _url(raw: bytes, mime: str = "image/jpeg") -> str:
    return f"data:{mime};base64," + base64.b64encode(raw).decode()


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    monkeypatch.setattr(main, "PLAN_DIR", str(tmp_path / "plan_images"))
    monkeypatch.setattr(main, "PICTURE_DIR", str(tmp_path / "pictures"))
    return TestClient(main.app)


def _quote(images=None, quote_id="QT-PIC-1", client_name="Puan Aminah"):
    body = {
        "quote_id": quote_id,
        "wall": {"width_mm": 3000, "height_mm": 2700, "depth_mm": 150},
        "placed_cabinets": [
            {"cabinet_type": "base_800", "label": "Base 800", "width_mm": 800,
             "height_mm": 850, "depth_mm": 600},
        ],
        "client_name": client_name,
    }
    if images is not None:
        body["design_images"] = images
    return body


def _pdf_has_images(client, quote_id) -> bool:
    return b"/Subtype /Image" in client.get(f"/pdf/{quote_id}").content


def test_a_quote_without_pictures_is_unchanged(client):
    assert client.post("/quote", json=_quote()).status_code == 200
    assert "pictures" not in client.get("/api/projects/QT-PIC-1").json()
    assert not _pdf_has_images(client, "QT-PIC-1")
    assert client.get("/api/projects/QT-PIC-1/picture/1").status_code == 404
    assert client.get("/pictures/QT-PIC-1").status_code == 404


def test_pictures_are_stored_served_and_printed_in_the_pdf(client):
    front, angle = _image(colour="#c9a24f"), _image("PNG", colour="#3d6b69")
    response = client.post(
        "/quote", json=_quote([_url(front), _url(angle, "image/png")])
    )
    assert response.status_code == 200

    project = client.get("/api/projects/QT-PIC-1").json()
    assert project["pictures"] == [
        "/api/projects/QT-PIC-1/picture/1",
        "/api/projects/QT-PIC-1/picture/2",
    ]
    one = client.get(project["pictures"][0])
    two = client.get(project["pictures"][1])
    assert one.status_code == 200 and one.headers["content-type"] == "image/jpeg"
    assert one.content == front
    assert two.headers["content-type"] == "image/png" and two.content == angle
    assert client.get("/api/projects/QT-PIC-1/picture/3").status_code == 404
    assert client.get("/api/projects/QT-PIC-1/picture/0").status_code == 404

    pdf = client.get("/pdf/QT-PIC-1")
    assert pdf.status_code == 200
    assert pdf.content.count(b"/Subtype /Image") >= 2
    # The line-item table is still there.
    assert b"%PDF" in pdf.content[:8]


def test_the_page_the_client_opens_lists_the_pictures(client):
    client.post("/quote", json=_quote([_url(_image()), _url(_image())],
                                      client_name="<b>Tan</b> & Sons"))
    page = client.get("/pictures/QT-PIC-1")
    assert page.status_code == 200 and "text/html" in page.headers["content-type"]
    assert page.text.count("<img ") == 2
    assert "/api/projects/QT-PIC-1/picture/2" in page.text
    # The client's name is text, never markup.
    assert "<b>Tan</b>" not in page.text and "&lt;b&gt;Tan&lt;/b&gt;" in page.text


@pytest.mark.parametrize(
    "bad",
    [
        "not a data url",
        "data:image/jpeg;base64,@@@not-base64@@@",
        "data:image/gif;base64," + base64.b64encode(b"GIF89a....").decode(),
        # Says JPEG, is a PNG: the first bytes decide, not the label.
        "data:image/jpeg;base64," + base64.b64encode(_image("PNG")).decode(),
        "data:text/html;base64," + base64.b64encode(b"<script>alert(1)</script>").decode(),
    ],
)
def test_anything_that_is_not_a_picture_is_dropped_but_the_quote_still_works(client, bad):
    assert client.post("/quote", json=_quote([bad])).status_code == 200
    assert "pictures" not in client.get("/api/projects/QT-PIC-1").json()
    assert not os.path.exists(main.PICTURE_DIR) or not os.listdir(main.PICTURE_DIR)


def test_a_picture_over_the_size_limit_is_dropped(client, monkeypatch):
    monkeypatch.setattr(main, "MAX_PICTURE_BYTES", 500)
    big = _image(size=(800, 600))
    assert len(big) > 500
    assert client.post("/quote", json=_quote([_url(big)])).status_code == 200
    assert "pictures" not in client.get("/api/projects/QT-PIC-1").json()


def test_only_the_first_few_pictures_are_kept(client):
    many = [_url(_image(colour=f"#0{n}0000")) for n in range(9)]
    client.post("/quote", json=_quote(many))
    assert len(client.get("/api/projects/QT-PIC-1").json()["pictures"]) == main.MAX_PICTURES


def test_sending_the_quote_again_keeps_or_replaces_its_pictures(client):
    client.post("/quote", json=_quote([_url(_image()), _url(_image())]))
    # Again, with no pictures: it keeps what it had (and the PDF still shows them).
    client.post("/quote", json=_quote())
    again = client.get("/api/projects/QT-PIC-1").json()
    assert len(again["pictures"]) == 2 and _pdf_has_images(client, "QT-PIC-1")
    # With a new one: it replaces them all.
    client.post("/quote", json=_quote([_url(_image("PNG"), "image/png")]))
    replaced = client.get("/api/projects/QT-PIC-1").json()
    assert replaced["pictures"] == ["/api/projects/QT-PIC-1/picture/1"]
    assert client.get("/api/projects/QT-PIC-1/picture/2").status_code == 404
    assert client.get("/api/projects/QT-PIC-1/picture/1").headers["content-type"] == "image/png"


def test_a_quote_id_cannot_write_outside_the_picture_folder(client, tmp_path):
    assert main._store_pictures("../escape", [_url(_image())]) == []
    assert main._store_pictures("QT-A/../../b", [_url(_image())]) == []
    assert not list(tmp_path.rglob("*escape*"))
    assert client.get("/api/projects/..%2Fx/picture/1").status_code in (404, 422)


def test_studio_saves_keep_the_pictures(client):
    client.post("/quote", json=_quote([_url(_image())]))
    saved = client.put("/api/projects/QT-PIC-1", json={"style": "nordic"})
    assert saved.status_code == 200
    assert client.get("/api/projects/QT-PIC-1").json()["pictures"] == ["/api/projects/QT-PIC-1/picture/1"]


# ── Pictures taken before the quote is sent (the app's Pictures button) ─────


def test_pictures_can_be_uploaded_before_there_is_a_quote(client):
    reply = client.post("/api/projects/QT-PIC-9/pictures",
                        json={"images": [_url(_image()), _url(_image("PNG"), "image/png")]})
    assert reply.status_code == 200
    assert reply.json() == {
        "count": 2,
        "urls": ["/api/projects/QT-PIC-9/picture/1", "/api/projects/QT-PIC-9/picture/2"],
        "page_url": "/pictures/QT-PIC-9",
    }
    assert client.get("/api/projects/QT-PIC-9/picture/2").headers["content-type"] == "image/png"
    assert client.get("/pictures/QT-PIC-9").status_code == 200


def test_an_upload_updates_the_project_if_there_is_one_and_replaces_the_old_pictures(client):
    client.post("/quote", json=_quote([_url(_image()), _url(_image())]))
    client.post("/api/projects/QT-PIC-1/pictures", json={"images": [_url(_image())]})
    assert client.get("/api/projects/QT-PIC-1").json()["pictures"] == ["/api/projects/QT-PIC-1/picture/1"]
    assert client.get("/api/projects/QT-PIC-1/picture/2").status_code == 404


@pytest.mark.parametrize("images", [[], ["nope"], ["data:image/jpeg;base64,AAAA"]])
def test_an_upload_with_nothing_usable_is_refused_and_changes_nothing(client, images):
    client.post("/quote", json=_quote([_url(_image())]))
    reply = client.post("/api/projects/QT-PIC-1/pictures", json={"images": images})
    assert reply.status_code == 422
    assert client.get("/api/projects/QT-PIC-1/picture/1").status_code == 200


def test_an_upload_for_a_bad_quote_id_is_refused(client, tmp_path):
    assert client.post("/api/projects/not-a-quote/pictures", json={"images": [_url(_image())]}).status_code == 404
    assert not (tmp_path / "pictures").exists()
