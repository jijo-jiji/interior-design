import os
import shutil
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest
from fastapi.testclient import TestClient
from backend import main
from backend.main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def scratch_storage(tmp_path, monkeypatch):
    """Every test here works on a scratch copy of the project database and
    scratch PDF and floor plan folders, so the quotes, revisions and deposits
    it sends never reach the real ones. The copy keeps the sample projects
    (QT-816BB0DC, QT-992AC14B) the export and portal tests read.

    The price list is a scratch store too: PUT /api/catalog saves a new
    version, and without this it would land in the real catalog_store and
    every later test in the run (the pricing contract among them) would
    price with the edited figures."""
    db = tmp_path / "projects_db.json"
    shutil.copyfile(main.DB_PATH, db)
    monkeypatch.setattr(main, "DB_PATH", str(db))
    monkeypatch.setattr(main, "PDF_DIR", str(tmp_path / "pdfs"))
    monkeypatch.setattr(main, "PLAN_DIR", str(tmp_path / "plan_images"))
    monkeypatch.setattr(
        main, "catalogs", main.catalog_lib.CatalogStore(tmp_path / "catalog_store"))


def test_list_projects():
    resp = client.get("/api/projects")
    assert resp.status_code == 200
    projects = resp.json()
    assert isinstance(projects, list)
    assert len(projects) >= 2
    assert any(p["quote_id"] == "QT-816BB0DC" for p in projects)
    print("[PASS] test_list_projects: returned", len(projects), "projects")

def test_get_single_project():
    resp = client.get("/api/projects/QT-816BB0DC")
    assert resp.status_code == 200
    data = resp.json()
    assert data["client_name"] == "Emma Watson"
    assert data["style_archetype"] == "industrial"
    assert len(data["placed_cabinets"]) == 4
    print("[PASS] test_get_single_project: loaded project successfully")

def test_catalog_endpoints():
    # GET catalog
    resp = client.get("/api/catalog")
    assert resp.status_code == 200
    cat = resp.json()
    assert "cabinets" in cat
    assert "styles" in cat

    # PUT catalog
    put_resp = client.put("/api/catalog", json={
        "cabinets": {"base_800": 435.0},
        "labour_rate_per_cabinet": 125.0
    })
    assert put_resp.status_code == 200
    updated_cat = put_resp.json()["catalog"]
    assert updated_cat["cabinets"]["base_800"] == 435.0
    assert updated_cat["labour_rate_per_cabinet"] == 125.0
    print("[PASS] test_catalog_endpoints: catalog get & update verified")

def test_dxf_export():
    resp = client.get("/api/export/QT-992AC14B/dxf")
    assert resp.status_code == 200
    content = resp.text

    # Verify AutoCAD Release 12 DXF headers and structure
    assert "AC1009" in content
    assert "SECTION" in content
    assert "ENTITIES" in content
    assert "LINE" in content
    assert "TEXT" in content
    assert "WALL_MAIN" in content
    assert "WALL_RETURN" in content
    assert "PART_NUMBERS" in content
    assert "CABINETS_BASE" in content
    assert "DIMENSIONS" in content
    assert "EOF" in content
    print("[PASS] test_dxf_export: valid AutoCAD R12 DXF with multi-wall & part numbers generated (length:", len(content), "bytes)")

def test_cutlist_export():
    resp = client.get("/api/export/QT-992AC14B/cutlist")
    assert resp.status_code == 200
    assert "text/csv" in resp.headers["content-type"]
    lines = resp.text.strip().split("\n")
    assert len(lines) >= 15  # 4 cabinets generate 25+ parts
    header = lines[0]
    assert "Part_ID" in header
    assert "Cabinet_Ref" in header
    assert "Material_Core" in header
    assert "Length_mm" in header
    assert "Width_mm" in header
    assert "Edgebanding_Spec" in header

    # Verify part IDs format (e.g. P0001, CAB-01)
    assert "CAB-01" in resp.text
    assert "P0001" in resp.text
    print(f"[PASS] test_cutlist_export: CNC cutting schedule CSV validated ({len(lines)} parts listed)")

def test_quote_preserves_coordinates():
    req_payload = {
        "wall": {
            "width_mm": 4200.0,
            "height_mm": 2700.0,
            "depth_mm": 150.0,
            "shape": "lShape",
            "return_mm": 2400.0,
        },
        "obstacles": [],
        "placed_cabinets": [
            {
                "cabinet_type": "base_800",
                "label": "Base 800mm",
                "width_mm": 800.0,
                "height_mm": 850.0,
                "depth_mm": 600.0,
                "x_mm": -1250.0,
                "y_mm": 0.0,
                "z_mm": 0.0,
                "wall_index": 0,
            }
        ],
        "salesperson_id": "rep_sydney_02",
        "style_archetype": "nordic",
        "client_name": "Test Coordinate Client",
        "deposit_paid": 250.0,
    }
    resp = client.post("/quote", json=req_payload)
    assert resp.status_code == 200
    res_data = resp.json()
    quote_id = res_data["quote_id"]

    # Verify project in DB preserved x_mm and shape
    proj_resp = client.get(f"/api/projects/{quote_id}")
    assert proj_resp.status_code == 200
    proj = proj_resp.json()
    assert proj["wall"]["shape"] == "lShape"
    assert proj["wall"]["return_mm"] == 2400.0
    cabs = proj["placed_cabinets"]
    assert len(cabs) == 1
    assert cabs[0]["x_mm"] == -1250.0
    assert cabs[0]["wall_index"] == 0
    print("[PASS] test_quote_preserves_coordinates: spatial coordinates & multi-wall specs intact")

def test_update_project_revisions():
    # Create an isolated test quote
    create_resp = client.post("/quote", json={
        "wall": {"width_mm": 3000.0, "height_mm": 2700.0, "depth_mm": 150.0},
        "obstacles": [],
        "placed_cabinets": [],
        "salesperson_id": "test_rep",
        "style_archetype": "japandi"
    })
    test_id = create_resp.json()["quote_id"]

    # Test PUT /api/projects/{test_id}
    resp = client.put(f"/api/projects/{test_id}", json={
        "subtotal": 5200.0,
        "gst": 520.0,
        "total_price": 5720.0,
        "placed_cabinets": [
            {"cabinet_type": "base_800", "label": "Base 800mm", "width_mm": 800, "height_mm": 850, "depth_mm": 600, "x_mm": -100.0}
        ]
    })
    assert resp.status_code == 200
    res_data = resp.json()
    assert res_data["status"] == "updated"
    assert res_data["project"]["total_price"] == 5720.0
    assert len(res_data["project"]["placed_cabinets"]) == 1
    print("[PASS] test_update_project_revisions: studio PUT persistence verified")

def test_customer_portal_and_deposit():
    # 1. Test redirect from /view/{id} to /portal/?id={id}
    resp = client.get("/view/QT-992AC14B", follow_redirects=False)
    assert resp.status_code in (302, 307)
    assert "/portal/?id=QT-992AC14B" in resp.headers["location"]

    # 2. Test static portal HTML exists
    portal_resp = client.get("/portal/?id=QT-992AC14B")
    assert portal_resp.status_code == 200
    assert "Client Portal" in portal_resp.text

    # 3. Test deposit endpoint
    dep_resp = client.post("/api/projects/QT-992AC14B/deposit")
    assert dep_resp.status_code == 200
    dep_data = dep_resp.json()
    assert dep_data["deposit_paid"] == 250.0

    # Verify project deposit state
    proj_resp = client.get("/api/projects/QT-992AC14B")
    assert proj_resp.json()["deposit_paid"] == 250.0
    print("[PASS] test_customer_portal_and_deposit: portal routing and deposit payment verified")

if __name__ == "__main__":
    # Through pytest, so the scratch storage above applies here too.
    raise SystemExit(pytest.main([__file__, "-v", "-s"]))
