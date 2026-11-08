"""The catalogue: data, versions, the width-based price rule, and the API.

Run from the repo root:  python -m pytest backend/test_catalog.py
"""

import os
import sys

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import catalog as catalog_lib  # noqa: E402
from backend import main  # noqa: E402
from backend.catalog import CatalogStore, default_catalog, price_layout  # noqa: E402


@pytest.fixture
def store(tmp_path):
    return CatalogStore(tmp_path / "store")


@pytest.fixture
def client(store, monkeypatch):
    monkeypatch.setattr(main, "catalogs", store)
    monkeypatch.setattr(main, "DB_PATH", str(store.directory.parent / "projects_db.json"))
    monkeypatch.setattr(main, "PDF_DIR", str(store.directory.parent / "pdfs"))
    monkeypatch.delenv("CATALOG_ADMIN_KEY", raising=False)
    return TestClient(main.app)


def _doc(store):
    return store.current().model_dump(mode="json")


# ── The sample data ─────────────────────────────────────────────────────────


def test_the_sample_catalogue_is_valid_and_marked_as_sample():
    catalog = default_catalog()
    assert catalog.version == 1
    assert catalog.is_placeholder is True
    assert catalog.tax.label == "SST"
    assert {m.type for m in catalog.modules} >= {"base_800", "base_600", "wall_600", "tall_600"}


# ── Pricing rule ────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "type_, width, expected",
    [
        ("base_800", 800, 420),          # fixed module: its own price
        ("base_600", 600, 340),
        ("sink_600", 600, 480),          # appliance module: fixed price
        ("base_450", 450, 280),          # 340 + (450-600)/100*40
        ("base_drawer_900", 900, 460),   # 340 + 3*40
        ("base_sink_800", 800, 560),     # 480 + 2*40
        ("base_hob_600", 600, 520),
        ("wall_900", 900, 400),          # 280 + 3*40
        ("wall_450", 450, 220),
        ("tall_700", 700, 660),
        ("filler_base", 100, 40),        # 0 + 1*40
        ("filler_wall", 75, 30),
        ("island_1200", 1200, 300),      # no family: the unknown-module price
    ],
)
def test_unit_price(type_, width, expected):
    assert default_catalog().unit_price(type_, width) == pytest.approx(expected)


def test_a_missing_width_prices_at_the_reference_width():
    assert default_catalog().unit_price("base_450", None) == pytest.approx(340)


def test_the_longest_prefix_wins():
    catalog = default_catalog()
    assert catalog.family_for("base_sink_900").id == "sink_unit"
    assert catalog.family_for("base_drawer_450").id == "drawer"
    assert catalog.family_for("base_450").id == "base"
    assert catalog.family_for("sink_600").id == "sink"
    assert catalog.family_for("nothing") is None


def test_a_generated_l_kitchen_is_priced_by_width_not_a_flat_300():
    cabinets = [
        ("corner_900", 900), ("base_450", 450), ("base_hob_600", 600), ("base_450", 450),
        ("tall_600", 600), ("filler_base", 100), ("base_sink_800", 800), ("base_600", 600),
        ("wall_900", 900), ("wall_450", 450), ("wall_450", 450), ("filler_wall", 100),
    ]
    lines, subtotal, tax, total = price_layout(default_catalog(), cabinets, [], "japandi", None)
    by_desc = {line["description"]: line for line in lines}
    # Grouped by type and width, so the 450s share a line and the fillers don't.
    assert by_desc["Cabinet — Base 450 (Japandi Natural)"]["qty"] == 2
    assert by_desc["Cabinet — Base 450 (Japandi Natural)"]["unit_price"] == 280
    assert by_desc["Cabinet — Filler Base 100 (Japandi Natural)"]["total"] == 40
    # Fillers are trim: no installation labour for them (10 of the 12 pieces).
    assert by_desc["Installation Labour"]["qty"] == 10
    # 580+560+520+620+40+560+340+400+440+40 = 4100, + 10 x 120 labour.
    assert subtotal == pytest.approx(5300)
    assert tax == pytest.approx(424)
    assert total == pytest.approx(5724)


def test_the_benchtop_runs_over_fillers_between_base_units_but_not_wall_fillers():
    catalog = default_catalog()
    metres = catalog.benchtop_metres("filler_base", 100) + catalog.benchtop_metres("filler_wall", 100)
    assert metres == pytest.approx(0.1)


def test_an_obstacle_alone_never_makes_a_negative_quote():
    _, subtotal, _, total = price_layout(default_catalog(), [], ["window", "door"], "japandi", None)
    assert subtotal == 0 and total == 0


# ── The store and its versions ──────────────────────────────────────────────


def test_the_first_run_seeds_version_1(store):
    assert store.current().version == 1
    assert [v["version"] for v in store.versions()] == [1]
    assert (store.directory / "current.json").exists()


def test_saving_makes_a_new_version_and_keeps_the_old_one(store):
    doc = _doc(store)
    doc["labour_rate_per_cabinet"] = 150
    saved = store.save(doc, base_version=1)
    assert saved.version == 2 and saved.updated_at
    assert store.get_version(1).labour_rate_per_cabinet == 120   # history is intact
    assert store.get_version(2).labour_rate_per_cabinet == 150
    assert store.get_version(99) is None


def test_a_saved_catalogue_survives_a_restart(store, tmp_path):
    doc = _doc(store)
    doc["is_placeholder"] = False
    doc["name"] = "SS Love 2026 price list"
    store.save(doc, 1)
    reopened = CatalogStore(store.directory)
    assert reopened.current().version == 2
    assert reopened.current().name == "SS Love 2026 price list"
    assert reopened.current().is_placeholder is False


def test_saving_from_a_stale_version_is_refused(store):
    store.save(_doc(store), 1)  # someone else saves first (now version 2)
    with pytest.raises(catalog_lib.CatalogConflict):
        store.save(_doc(store), 1)
    assert store.current().version == 2


def test_a_damaged_current_file_falls_back_to_the_newest_good_version(store):
    doc = _doc(store)
    doc["labour_rate_per_cabinet"] = 140
    store.save(doc, 1)
    (store.directory / "current.json").write_text("{ not json")
    reopened = CatalogStore(store.directory)
    assert reopened.current().version == 2
    assert reopened.current().labour_rate_per_cabinet == 140


@pytest.mark.parametrize(
    "change, message",
    [
        (lambda d: d["style_options"]["japandi"].update(multiplier=0), "multiplier"),
        (lambda d: d["modules"].append(dict(d["modules"][0])), "listed twice"),
        (lambda d: d["tax"].update(rate=0.9), "rate"),
        (lambda d: d["families"].append({**d["families"][0], "id": "again"}), "two families"),
        (lambda d: d["layout"]["base_door_widths_mm"].append(600), "listed twice"),
        (lambda d: d["layout"]["rules"].update(min_filler_mm=500, max_filler_mm=100), "larger than"),
        (lambda d: d.update(surprise=1), "surprise"),
    ],
)
def test_nonsense_is_rejected_with_a_reason(store, change, message):
    doc = _doc(store)
    change(doc)
    with pytest.raises(catalog_lib.ValidationError) as err:
        store.save(doc, 1)
    assert message in str(err.value)
    assert store.current().version == 1


# ── The API ─────────────────────────────────────────────────────────────────


def test_get_keeps_the_flat_maps_older_clients_read(client):
    cat = client.get("/api/catalog").json()
    assert cat["cabinets"]["base_800"] == 420
    assert cat["styles"]["industrial"] == 1.18
    assert cat["style_names"]["japandi"] == "Japandi Natural"
    assert cat["benchtops"]["granite_black"] == 480
    assert cat["gst_rate"] == 0.08
    assert cat["version"] == 1 and cat["is_placeholder"] is True
    assert cat["requires_admin_key"] is False


def test_put_the_whole_catalogue_then_read_it_back(client):
    doc = client.get("/api/catalog").json()
    sent = {k: v for k, v in doc.items() if k not in (
        "cabinets", "styles", "style_names", "benchtops", "benchtop_names", "gst_rate", "requires_admin_key")}
    sent["base_version"] = doc["version"]
    sent["modules"][0]["price"] = 455
    response = client.put("/api/catalog", json=sent)
    assert response.status_code == 200, response.text
    assert response.json()["catalog"]["version"] == 2
    assert client.get("/api/catalog").json()["cabinets"]["base_800"] == 455
    assert client.get("/api/catalog", params={"version": 1}).json()["cabinets"]["base_800"] == 420
    assert client.get("/api/catalog", params={"version": 7}).status_code == 404
    versions = client.get("/api/catalog/versions").json()
    assert versions["current"] == 2 and [v["version"] for v in versions["versions"]] == [1, 2]


def test_put_from_a_stale_version_is_a_409(client):
    doc = client.get("/api/catalog").json()
    sent = {k: v for k, v in doc.items() if k in main.catalogs.current().model_dump()}
    sent["base_version"] = 1
    assert client.put("/api/catalog", json=sent).status_code == 200
    assert client.put("/api/catalog", json=sent).status_code == 409


def test_put_nonsense_is_a_422_that_says_where(client):
    doc = client.get("/api/catalog").json()
    sent = {k: v for k, v in doc.items() if k in main.catalogs.current().model_dump()}
    sent["style_options"]["japandi"]["multiplier"] = -1
    response = client.put("/api/catalog", json=sent)
    assert response.status_code == 422
    assert any("japandi" in item["where"] for item in response.json()["detail"])


def test_the_old_partial_put_still_works(client):
    response = client.put("/api/catalog", json={
        "cabinets": {"base_800": 435.0}, "labour_rate_per_cabinet": 125.0,
    })
    assert response.status_code == 200
    cat = response.json()["catalog"]
    assert cat["cabinets"]["base_800"] == 435.0 and cat["labour_rate_per_cabinet"] == 125.0
    assert cat["version"] == 2


def test_an_admin_key_can_lock_editing(client, monkeypatch):
    monkeypatch.setenv("CATALOG_ADMIN_KEY", "s3cret")
    payload = {"labour_rate_per_cabinet": 130}
    assert client.get("/api/catalog").json()["requires_admin_key"] is True
    assert client.get("/api/catalog").status_code == 200           # reading stays open
    assert client.put("/api/catalog", json=payload).status_code == 401
    assert client.put("/api/catalog", json=payload, headers={"X-Admin-Key": "wrong"}).status_code == 401
    assert client.put("/api/catalog", json=payload, headers={"X-Admin-Key": "s3cret"}).status_code == 200


# ── Quotes use the catalogue version the app priced with ───────────────────


def _quote_body(version=None):
    body = {
        "quote_id": "QT-CAT-1",
        "wall": {"width_mm": 3000, "height_mm": 2700, "depth_mm": 150},
        "placed_cabinets": [
            {"cabinet_type": "base_800", "label": "Base 800", "width_mm": 800,
             "height_mm": 850, "depth_mm": 600},
        ],
        "style_archetype": "japandi",
        "client_name": "Puan Aminah",
    }
    if version is not None:
        body["catalog_version"] = version
    return body


def test_a_quote_made_offline_is_priced_with_the_version_it_was_shown(client, store):
    client.put("/api/catalog", json={"cabinets": {"base_800": 500.0}})   # version 2: dearer
    # The tablet last synced version 1 (base_800 = 420) and quoted from it.
    old = client.post("/quote", json=_quote_body(version=1)).json()
    assert old["subtotal"] == pytest.approx(420 + 120)
    # A quote with no version uses the current prices.
    new = client.post("/quote", json={**_quote_body(), "quote_id": "QT-CAT-2"}).json()
    assert new["subtotal"] == pytest.approx(500 + 120)
    stored = client.get("/api/projects/QT-CAT-1").json()
    assert stored["catalog_version"] == 1


def test_an_unknown_version_falls_back_to_the_current_catalogue(client):
    quote = client.post("/quote", json=_quote_body(version=99)).json()
    assert quote["subtotal"] == pytest.approx(420 + 120)
