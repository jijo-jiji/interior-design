"""
Static Trace — FastAPI Backend
Handles pricing, PDF generation, and CRM lead logging.
The Flutter app calls POST /quote when the salesperson finalises a layout.
"""

from __future__ import annotations

import html
import io
import json
import math
import uuid
from datetime import datetime
from typing import Any

import uvicorn
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (
    SimpleDocTemplate,
    Table,
    TableStyle,
    Paragraph,
    Spacer,
    Image as RLImage,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
import os
import re
import tempfile
import base64

try:
    from backend.dxf_exporter import generate_dxf
    from backend.cutlist_generator import generate_cutlist_csv
    from backend import catalog as catalog_lib
except ImportError:
    from dxf_exporter import generate_dxf
    from cutlist_generator import generate_cutlist_csv
    import catalog as catalog_lib

# HTTPS for the browser sales app (needs the `cryptography` package; without
# it the server still runs, over http only).
try:
    try:
        from backend import office_https
    except ImportError:
        import office_https
except ImportError:
    office_https = None

# ─── App ─────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Static Trace API",
    version="1.0.0",
    description="Pricing engine and PDF quotation generator for kitchen layouts.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Set by `python main.py` when the secure (https) server is running.
app.state.https_port = None


@app.middleware("http")
async def sales_app_over_https(request: Request, call_next):
    """Browsers only allow the camera on https, so the sales app at
    http://...:8000/sales is sent to the same page on the https port."""
    https_port = app.state.https_port
    path = request.url.path
    if (
        https_port
        and request.url.scheme == "http"
        and (path == "/sales" or path.startswith("/sales/"))
    ):
        host = request.url.hostname or "localhost"
        if ":" in host:  # IPv6 literal
            host = f"[{host}]"
        target = request.url.replace(scheme="https", netloc=f"{host}:{https_port}")
        return RedirectResponse(str(target), status_code=307)
    return await call_next(request)

# ─── Catalogue ───────────────────────────────────────────────────────────────
# Prices, sizes, finishes, tax and the pricing rules are data, not code: see
# catalog.py. The store keeps the current catalogue and every earlier version.
catalogs = catalog_lib.CatalogStore()

# ─── Schemas ─────────────────────────────────────────────────────────────────

class WallSpec(BaseModel):
    width_mm: float
    height_mm: float
    depth_mm: float
    shape: str = "singleWall"
    return_mm: float = 0.0
    aisle_mm: float = 0.0

class ObstacleSpec(BaseModel):
    type: str
    distance_from_left_mm: float
    distance_from_floor_mm: float
    width_mm: float
    height_mm: float
    # An opening to be made in a solid wall (sales app wall card): the
    # catalogue's wall_work.openings key ("hidden_door", "door", "window").
    # Priced on the quote. None for a door or window that is already there.
    work: str | None = None

class PlacedCabinet(BaseModel):
    # Keep anything else the apps send: dropping fields here used to lose the
    # generator's kind, side-wall position and mounting height on every quote.
    model_config = ConfigDict(extra="allow")

    cabinet_type: str
    label: str = ""
    width_mm: float
    height_mm: float
    depth_mm: float
    x_mm: float = 0.0
    y_mm: float = 0.0
    z_mm: float = 0.0
    wall_index: int = 0
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    # Generated layouts (sales app): how it's drawn, which wall, where.
    kind: str | None = None
    run: str = "main"
    offset_mm: float | None = None
    mount_mm: float | None = None
    generated: bool = False

class QuoteRequest(BaseModel):
    quote_id: str | None = None
    wall: WallSpec
    obstacles: list[ObstacleSpec] = []
    placed_cabinets: list[PlacedCabinet] = []
    salesperson_id: str = "demo_agent_01"
    style_archetype: str = "japandi"
    benchtop_material: str | None = None
    client_name: str | None = None
    client_phone: str | None = None
    client_email: str | None = None
    deposit_paid: float = 0.0
    signature_base64: str | None = None
    # The catalogue version the app priced this with. The server prices with
    # the same version, so a quote made offline against an older price list
    # still prints the number the client was shown.
    catalog_version: int | None = None
    # The floor plan the room was read from (sales app, floor plan route),
    # for the Room and House views: the picture as a data URL, plus walls
    # and rooms in mm from the kitchen's corner. The picture is stored as a
    # file; the project keeps its address.
    floor_plan: dict[str, Any] | None = None
    # How the wall was measured on the photo (sales app, camera route): its
    # four corners as fractions of the photo, the photo's size and lens, how
    # the phone was held. For checking a design against a tape later, and as
    # labelled photos for a learned corner finder.
    capture: dict[str, Any] | None = None
    # The wall photo itself (a JPEG or PNG data URL), kept with the corners as
    # a labelled photo. keep_wall_photo is the client's choice on the quote
    # sheet: False removes any copy kept before.
    wall_photo: str | None = None
    keep_wall_photo: bool = True
    # Pictures of the design (the 3D page's "Save picture"): data URLs, JPEG
    # or PNG, up to MAX_PICTURES. The server stores them as files, prints
    # them in the quote PDF and serves them to the client.
    design_images: list[str] = []
    # How the design was dressed in the pictures (sales app "Look"): doors,
    # backsplash, decor, light. Presentation only; the quote says what in it
    # is not part of the price.
    scene: dict[str, Any] | None = None
    # The finish over the wall (sales app wall card): {"kind": "paint" |
    # "tiles" | "panels", "area_m2": 9.72, "colour": "#d9d4cc"}. Priced per
    # square metre from the catalogue's wall_work.finishes.
    wall_finish: dict[str, Any] | None = None

class LineItem(BaseModel):
    description: str
    qty: int
    unit_price: float
    total: float

class QuoteResponse(BaseModel):
    quote_id: str
    salesperson_id: str
    created_at: str
    line_items: list[LineItem]
    subtotal: float
    gst: float
    total_price: float
    pdf_url: str

# ─── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "service": "static-trace-api"}


def _catalog_for(request: "QuoteRequest") -> "catalog_lib.Catalog":
    """The catalogue version the app priced with, else the current one."""
    if request.catalog_version is not None:
        found = catalogs.get_version(request.catalog_version)
        if found is not None:
            return found
    return catalogs.current()


def price_quote(
    request: QuoteRequest,
    catalog: "catalog_lib.Catalog | None" = None,
) -> tuple[list[LineItem], float, float, float]:
    """Prices a layout: (line_items, subtotal, tax, total).

    Pure — no database, no PDF — so the pricing contract can be tested against
    the mobile CPQEngine and the Studio without side effects. See
    test/fixtures/pricing_cases.json. Pass [catalog] to price against a
    specific catalogue (the contract test uses the sample one).
    """
    catalog = catalog or _catalog_for(request)
    lines, subtotal, tax, total = catalog_lib.price_layout(
        catalog,
        [(c.cabinet_type, c.width_mm) for c in request.placed_cabinets],
        [o.type for o in request.obstacles],
        request.style_archetype,
        request.benchtop_material,
        wall_work=[o.work for o in request.obstacles if o.work],
        wall_finish=_clean_wall_finish(request.wall_finish),
    )
    return [LineItem(**line) for line in lines], subtotal, tax, total


@app.post("/quote", response_model=QuoteResponse)
def create_quote(request: QuoteRequest):
    quote_id = request.quote_id if (request.quote_id and request.quote_id.startswith("QT-")) else f"QT-{uuid.uuid4().hex[:8].upper()}"

    catalog = _catalog_for(request)
    line_items, subtotal, gst, total_price = price_quote(request, catalog)

    # Pictures first, so the PDF can print them. A quote sent again without
    # new pictures keeps the ones it had.
    pictures = _store_pictures(quote_id, request.design_images)

    # The wall photo, only with the corners marked on it (a photo without
    # them teaches nothing), and only if the client agreed.
    capture = _clean_capture(request.capture)
    wall_photo_kept = _store_wall_photo(
        quote_id, request.wall_photo if capture else None, request.keep_wall_photo)

    # Generate PDF
    pdf_path = _generate_pdf(
        quote_id=quote_id,
        request=request,
        line_items=line_items,
        subtotal=subtotal,
        gst=gst,
        total_price=total_price,
        catalog=catalog,
        pictures=[path for path, _ in pictures],
        scene=_clean_scene(request.scene),
        wall_photo_kept=wall_photo_kept,
    )

    # Store path for /pdf/<id> retrieval
    _pdf_store[quote_id] = pdf_path

    # Save to persistent projects DB
    record = {
        "quote_id": quote_id,
        "salesperson_id": request.salesperson_id,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "client_name": request.client_name or "Client Walk-in",
        "client_phone": request.client_phone or "",
        "client_email": request.client_email or "",
        "deposit_paid": request.deposit_paid,
        "style_archetype": request.style_archetype,
        "benchtop_material": request.benchtop_material,
        "catalog_version": catalog.version,
        "wall": request.wall.dict(),
        "obstacles": [o.dict() for o in request.obstacles],
        "placed_cabinets": [c.dict() for c in request.placed_cabinets],
        "line_items": [li.dict() for li in line_items],
        "subtotal": round(subtotal, 2),
        "gst": gst,
        "total_price": total_price,
        "pdf_path": pdf_path,
        "pdf_url": f"/pdf/{quote_id}",
        "has_signature": bool(request.signature_base64),
    }
    if request.floor_plan:
        record["floor_plan"] = _store_floor_plan(quote_id, request.floor_plan)
    if capture:
        if wall_photo_kept:
            capture["photo_kept"] = True
        record["capture"] = capture
    look = _clean_scene(request.scene)
    if look:
        record["scene"] = look
    wall_finish = _clean_wall_finish(request.wall_finish)
    if wall_finish:
        record["wall_finish"] = wall_finish
    if pictures:
        record["pictures"] = [f"/api/projects/{quote_id}/picture/{n}" for n in range(1, len(pictures) + 1)]
    db = _load_projects_db()
    db[quote_id] = record
    _save_projects_db(db)

    return QuoteResponse(
        quote_id=quote_id,
        salesperson_id=request.salesperson_id,
        created_at=record["created_at"],
        line_items=line_items,
        subtotal=round(subtotal, 2),
        gst=gst,
        total_price=total_price,
        pdf_url=f"/pdf/{quote_id}",
    )


# ─── Persistent Project Database ──────────────────────────────────────────────
DB_PATH = os.path.join(os.path.dirname(__file__), "projects_db.json")
PDF_DIR = os.path.join(os.path.dirname(__file__), "generated_pdfs")
# Floor plan pictures, one per quote: kept out of projects_db.json, which
# would grow by hundreds of KB per plan.
PLAN_DIR = os.path.join(os.path.dirname(__file__), "plan_images")
# Pictures of the design, a few per quote, kept out of projects_db.json too.
PICTURE_DIR = os.path.join(os.path.dirname(__file__), "design_pictures")
MAX_PICTURES = 6
MAX_PICTURE_BYTES = 6 * 1024 * 1024
_pdf_store: dict[str, str] = {}

_QUOTE_ID = re.compile(r"^QT-[A-Za-z0-9-]{1,40}$")
MAX_PLAN_IMAGE_BYTES = 8 * 1024 * 1024
# Wall photos the camera route measured from, kept with their corners as
# labelled photos for training a corner finder (see _store_wall_photo).
WALL_PHOTO_DIR = os.path.join(os.path.dirname(__file__), "wall_photos")
MAX_WALL_PHOTO_BYTES = 8 * 1024 * 1024
WALL_PHOTO_LONG_SIDE = 2400


def _wall_photo_path(quote_id: str) -> str:
    return os.path.join(WALL_PHOTO_DIR, f"{quote_id}.jpg")


def _store_wall_photo(quote_id: str, data_url: str | None, keep: bool) -> bool:
    """Keeps the wall photo a quote was measured from, or removes it when the
    client said no. Returns whether the quote now has one.

    Saved upright (as the app showed it, so the corners line up) and without
    the photo's metadata: a phone photo can carry the home's GPS position.
    Never served back out: it is training data, not part of the quote."""
    if not _QUOTE_ID.match(quote_id):
        return False
    path = _wall_photo_path(quote_id)
    if not keep:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        return False
    if isinstance(data_url, str):
        for prefix in ("data:image/jpeg;base64,", "data:image/png;base64,"):
            if data_url.startswith(prefix):
                try:
                    raw = base64.b64decode(data_url[len(prefix):], validate=True)
                except ValueError:
                    break
                if len(raw) <= MAX_WALL_PHOTO_BYTES:
                    _write_wall_photo(raw, path)
                break
    return os.path.exists(path)


def _write_wall_photo(raw: bytes, path: str) -> None:
    from PIL import Image, ImageOps

    try:
        with Image.open(io.BytesIO(raw)) as photo:
            if photo.format not in ("JPEG", "PNG"):
                return
            upright = ImageOps.exif_transpose(photo).convert("RGB")
    except Exception:
        return
    upright.thumbnail((WALL_PHOTO_LONG_SIDE, WALL_PHOTO_LONG_SIDE))
    os.makedirs(WALL_PHOTO_DIR, exist_ok=True)
    # No exif= argument: nothing of the original's metadata is written.
    upright.save(path, "JPEG", quality=90)


def _number(value: Any) -> float | None:
    """A plain finite number, or None (bools and strings are not numbers)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def _clean_corners(raw: Any, count: int = 4, low: float = 0, high: float = 1) -> list[list[float]] | None:
    """[count] [x, y] points, each a fraction of the photo (between low and
    high), or None."""
    if not (isinstance(raw, list) and len(raw) == count):
        return None
    clean = []
    for corner in raw:
        if not (isinstance(corner, list) and len(corner) == 2):
            return None
        xy = [_number(v) for v in corner]
        if any(v is None or not low <= v <= high for v in xy):
            return None
        clean.append(xy)
    return clean


def _clean_capture(raw: Any) -> dict[str, Any] | None:
    """The photo measurement, keeping only the fields the app sends, as plain
    numbers in range, so a project file can't fill up with a client's junk.
    Without four sensible corners there is nothing worth keeping."""
    if not isinstance(raw, dict):
        return None
    clean_corners = _clean_corners(raw.get("corners"))
    if clean_corners is None:
        return None
    out: dict[str, Any] = {"method": "corners", "corners": clean_corners}
    # Where the wall-corner model put them, if it found them: beside the
    # corners confirmed, it measures the model.
    suggested = _clean_corners(raw.get("suggested_corners"))
    if suggested is not None:
        out["suggested_corners"] = suggested
        # Found from the depth map's flat patches, or by our corner model.
        if raw.get("suggested_by") in ("planes", "learned"):
            out["suggested_by"] = raw["suggested_by"]
    # In a kitchen the bottom corners are marked where the floor meets the
    # cabinets; this is where the wall itself meets the floor behind them
    # (bottom-right, bottom-left), which the wall was measured from. It can
    # sit a little off the photo's edge.
    wall_bottom = _clean_corners(raw.get("wall_bottom"), count=2, low=-0.1, high=1.1)
    if wall_bottom is not None:
        out["wall_bottom"] = wall_bottom
    # Where the wall's size came from: worked out from the photo (by the
    # worktop's or a door's standard height, or an assumed ceiling), or typed.
    if raw.get("size_from") in ("worktop", "door", "assumed", "typed"):
        out["size_from"] = raw["size_from"]
    size = raw.get("photo_px")
    if isinstance(size, list) and len(size) == 2:
        wh = [_number(v) for v in size]
        if all(v is not None and 0 < v <= 20000 for v in wh):
            out["photo_px"] = [int(v) for v in wh]
    for key, low, high in (("focal_px", 1, 100000), ("photo_aspect", 0.05, 20)):
        v = _number(raw.get(key))
        if v is not None and low <= v <= high:
            out[key] = v
    if raw.get("focal_source") in ("photo", "corners", "assumed"):
        out["focal_source"] = raw["focal_source"]
    tilt = raw.get("tilt_deg")
    if isinstance(tilt, dict):
        angles = {k: _number(tilt.get(k)) for k in ("roll", "pitch")}
        if all(v is not None and -180 <= v <= 180 for v in angles.values()):
            out["tilt_deg"] = angles
    return out


def _store_floor_plan(quote_id: str, plan: dict[str, Any]) -> dict[str, Any]:
    """Saves the plan's picture as a file and points the plan at it. A plan
    already pointing at a stored picture (a design sent again) is kept."""
    stored = dict(plan)
    image = stored.get("image")
    prefix = "data:image/png;base64,"
    if isinstance(image, str) and image.startswith(prefix) and _QUOTE_ID.match(quote_id):
        try:
            png = base64.b64decode(image[len(prefix):], validate=True)
        except ValueError:
            png = b""
        if png.startswith(b"\x89PNG") and len(png) <= MAX_PLAN_IMAGE_BYTES:
            os.makedirs(PLAN_DIR, exist_ok=True)
            with open(os.path.join(PLAN_DIR, f"{quote_id}.png"), "wb") as f:
                f.write(png)
            stored["image"] = f"/api/projects/{quote_id}/plan.png"
        else:
            stored.pop("image", None)
    return stored


_PICTURE_TYPES = {
    "data:image/jpeg;base64,": (b"\xff\xd8\xff", ".jpg", "image/jpeg"),
    "data:image/png;base64,": (b"\x89PNG", ".png", "image/png"),
}


def _picture_files(quote_id: str) -> list[tuple[str, str]]:
    """A quote's stored pictures in order: (file path, media type)."""
    found = []
    if not _QUOTE_ID.match(quote_id):
        return found
    for n in range(1, MAX_PICTURES + 1):
        for _, ext, media in _PICTURE_TYPES.values():
            path = os.path.join(PICTURE_DIR, f"{quote_id}-{n}{ext}")
            if os.path.exists(path):
                found.append((path, media))
                break
    return found


def _accept_pictures(images: list[str]) -> list[tuple[bytes, str]]:
    """The pictures worth keeping: JPEG or PNG (the first bytes decide, not the
    label), within the size limit, at most MAX_PICTURES. Each as (bytes, ext)."""
    accepted: list[tuple[bytes, str]] = []
    for image in images[:MAX_PICTURES]:
        for prefix, (magic, ext, _) in _PICTURE_TYPES.items():
            if isinstance(image, str) and image.startswith(prefix):
                try:
                    raw = base64.b64decode(image[len(prefix):], validate=True)
                except ValueError:
                    break
                if raw.startswith(magic) and len(raw) <= MAX_PICTURE_BYTES:
                    accepted.append((raw, ext))
                break
    return accepted


def _write_pictures(quote_id: str, accepted: list[tuple[bytes, str]]) -> None:
    """Replaces a quote's stored pictures with [accepted]."""
    os.makedirs(PICTURE_DIR, exist_ok=True)
    for _, old_ext, _ in _PICTURE_TYPES.values():
        for n in range(1, MAX_PICTURES + 1):
            try:
                os.remove(os.path.join(PICTURE_DIR, f"{quote_id}-{n}{old_ext}"))
            except FileNotFoundError:
                pass
    for n, (raw, ext) in enumerate(accepted, start=1):
        with open(os.path.join(PICTURE_DIR, f"{quote_id}-{n}{ext}"), "wb") as f:
            f.write(raw)


def _store_pictures(quote_id: str, images: list[str]) -> list[tuple[str, str]]:
    """Saves the design pictures a quote came with and returns every picture
    the quote now has. Nothing that is not a usable picture is kept; with no
    usable new pictures the quote keeps the ones it had."""
    if not _QUOTE_ID.match(quote_id):
        return []
    accepted = _accept_pictures(images)
    if accepted:
        _write_pictures(quote_id, accepted)
    return _picture_files(quote_id)


def _load_projects_db() -> dict[str, Any]:
    if os.path.exists(DB_PATH):
        try:
            with open(DB_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def _save_projects_db(data: dict[str, Any]) -> None:
    try:
        with open(DB_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print("[DB Error]", e)


def _normalize_project(project: dict[str, Any]) -> dict[str, Any]:
    p = dict(project)
    quote_id = p.get("quote_id") or p.get("id") or ""
    p["id"] = quote_id
    p["quote_id"] = quote_id
    
    style = p.get("style_archetype") or p.get("style") or "japandi"
    p["style"] = style
    p["style_archetype"] = style

    # Normalize cabinets list. Every stored field is kept (kind, run,
    # offset_mm, mount_mm, generated…), so both apps can redraw exactly what
    # was designed; the missing ones are filled in.
    raw_cabs = p.get("placed_cabinets") or p.get("cabinets") or []
    wall = p.get("wall") or {}
    wall_w_m = float(wall.get("width_mm") or 3600.0) / 1000.0
    normalized_cabs = []
    normalized_placed = []

    for idx, c in enumerate(raw_cabs):
        cab_type = c.get("type") or c.get("cabinet_type") or "base_600"
        cab_id = c.get("id") or f"cab-{idx + 1}"

        width_m = c.get("width")
        if width_m is None and "width_mm" in c:
            width_m = float(c["width_mm"]) / 1000.0
        if width_m is None:
            width_m = 0.8 if cab_type == "base_800" else 0.6

        height_m = c.get("height")
        if height_m is None and "height_mm" in c:
            height_m = float(c["height_mm"]) / 1000.0
        if height_m is None:
            height_m = 2.1 if cab_type == "tall_600" else (0.7 if cab_type == "wall_600" else 0.85)

        depth_m = c.get("depth")
        if depth_m is None and "depth_mm" in c:
            depth_m = float(c["depth_mm"]) / 1000.0
        if depth_m is None:
            depth_m = 0.32 if cab_type == "wall_600" else 0.6

        # `x` (studio): left edge in metres from the left end of the wall.
        # `x_mm` (sales app, DXF): centre in mm from the centre of the wall.
        x_m = c.get("x")
        raw_x_mm = c.get("x_mm")
        if x_m is None:
            if raw_x_mm is not None:
                x_m = float(raw_x_mm) / 1000.0 + wall_w_m / 2.0 - width_m / 2.0
            elif "distance_from_left_mm" in c:
                x_m = float(c["distance_from_left_mm"]) / 1000.0
            else:
                x_m = 0.05 + idx * 0.65
        x_m = max(0.0, round(float(x_m), 3))
        centre_x_mm = (
            raw_x_mm
            if raw_x_mm is not None
            else round((x_m + width_m / 2.0 - wall_w_m / 2.0) * 1000.0)
        )
        kind = c.get("kind")
        is_wall_mounted = (
            (c.get("mount_mm") or 0) > 0
            or kind in ("wall", "hood")
            or cab_type.startswith(("wall", "rangehood"))
        )

        normalized_cabs.append({
            **c,
            "id": cab_id,
            "type": cab_type,
            "cabinet_type": cab_type,
            "width": width_m,
            "height": height_m,
            "depth": depth_m,
            "width_mm": round(width_m * 1000.0),
            "height_mm": round(height_m * 1000.0),
            "depth_mm": round(depth_m * 1000.0),
            "x": x_m,
            "x_mm": centre_x_mm,
            "distance_from_left_mm": round(x_m * 1000.0),
            "isWallMounted": is_wall_mounted,
        })

        normalized_placed.append({
            **c,
            "id": cab_id,
            "cabinet_type": cab_type,
            "label": c.get("label") or f"{cab_type.replace('_', ' ').title()}",
            "width_mm": round(width_m * 1000.0),
            "height_mm": round(height_m * 1000.0),
            "depth_mm": round(depth_m * 1000.0),
            "x_mm": centre_x_mm,
            "y_mm": c.get("y_mm", 0.0),
            "z_mm": c.get("z_mm", 0.0),
            "wall_index": c.get("wall_index", 1 if c.get("run") == "return" else 0),
        })

    p["cabinets"] = normalized_cabs
    p["placed_cabinets"] = normalized_placed
    return p


# ─── Studio Web Workbench REST Endpoints ─────────────────────────────────────

@app.get("/api/projects")
def list_projects():
    """Returns all projects / quotes submitted by mobile sales reps or studio."""
    db = _load_projects_db()
    items = [_normalize_project(item) for item in db.values()]
    items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return items


@app.get("/api/projects/{quote_id}")
def get_project(quote_id: str):
    """Retrieves full project JSON for 3D Studio inspection and editing."""
    db = _load_projects_db()
    project = db.get(quote_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    return _normalize_project(project)


@app.get("/api/projects/{quote_id}/plan.png")
def get_project_plan(quote_id: str):
    """The floor plan picture a project's room was read from."""
    path = os.path.join(PLAN_DIR, f"{quote_id}.png")
    if not _QUOTE_ID.match(quote_id) or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="No floor plan for this project")
    return FileResponse(path, media_type="image/png")


@app.get("/api/projects/{quote_id}/picture/{n}")
def get_project_picture(quote_id: str, n: int):
    """One picture of a project's design (1 is the first)."""
    files = _picture_files(quote_id)
    if n < 1 or n > len(files):
        raise HTTPException(status_code=404, detail="No such picture for this project")
    path, media = files[n - 1]
    return FileResponse(path, media_type=media, headers={"Cache-Control": "no-cache"})


class PicturesUpload(BaseModel):
    images: list[str]


@app.post("/api/projects/{quote_id}/pictures")
def upload_pictures(quote_id: str, body: PicturesUpload):
    """Pictures of a design taken before the quote is sent (the app's
    "Pictures" button), stored so the client can open them from a link. A
    quote sent later brings its own and replaces these."""
    if not _QUOTE_ID.match(quote_id):
        raise HTTPException(status_code=404, detail="Unknown quote")
    accepted = _accept_pictures(body.images)
    if not accepted:
        raise HTTPException(status_code=422, detail="No usable pictures (JPEG or PNG, within the size limit)")
    _write_pictures(quote_id, accepted)
    urls = [f"/api/projects/{quote_id}/picture/{n}" for n in range(1, len(accepted) + 1)]
    db = _load_projects_db()
    if quote_id in db:
        db[quote_id]["pictures"] = urls
        _save_projects_db(db)
    return {"count": len(urls), "urls": urls, "page_url": f"/pictures/{quote_id}"}


@app.get("/pictures/{quote_id}", response_class=HTMLResponse)
def pictures_page(quote_id: str):
    """What the client opens from the message: the pictures of their design,
    big on a phone, each with a Save link. The quote id is checked, so the
    page only ever holds file addresses the server made."""
    files = _picture_files(quote_id)
    if not files:
        raise HTTPException(status_code=404, detail="No pictures for this project")
    db = _load_projects_db()
    name = (db.get(quote_id) or {}).get("client_name") or ""
    heading = f"Your kitchen design" + (f", {name}" if name else "")
    note = _scene_note((db.get(quote_id) or {}).get("scene"))
    figures = "".join(
        f'<figure><img src="/api/projects/{quote_id}/picture/{n}" alt="Picture {n} of your kitchen design">'
        f'<figcaption><a href="/api/projects/{quote_id}/picture/{n}" download="kitchen-{quote_id}-{n}.jpg">Save picture {n}</a></figcaption></figure>'
        for n in range(1, len(files) + 1)
    )
    return HTMLResponse(
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{html.escape(heading)}</title>"
        "<style>body{margin:0;font-family:system-ui,sans-serif;background:#faf7f2;color:#241f1b}"
        "main{max-width:60rem;margin:0 auto;padding:1rem}h1{font-size:1.25rem}"
        "figure{margin:0 0 1.5rem}img{width:100%;height:auto;border-radius:.75rem;display:block}"
        "figcaption{padding:.5rem 0}a{color:#8f5238;font-weight:600}p{color:#574a3e;font-size:.9rem}</style></head><body><main>"
        f"<h1>{html.escape(heading)}</h1>{figures}"
        "<p>These pictures show the design. Colours and finishes may look slightly different from the real materials. "
        f"{html.escape(note)}</p>"
        "</main></body></html>"
    )


@app.put("/api/projects/{quote_id}")
def update_project(quote_id: str, updated: dict[str, Any]):
    """Saves studio modifications (repositioned cabinets, style changes)."""
    db = _load_projects_db()
    if quote_id not in db:
        raise HTTPException(status_code=404, detail="Project not found")
    
    project = db[quote_id]
    
    # Handle cabinets update from either web or mobile schema
    if "cabinets" in updated or "placed_cabinets" in updated:
        raw_cabs = updated.get("cabinets") or updated.get("placed_cabinets") or []
        project["cabinets"] = raw_cabs
        project["placed_cabinets"] = raw_cabs

    if "style" in updated or "style_archetype" in updated:
        style = updated.get("style") or updated.get("style_archetype")
        project["style"] = style
        project["style_archetype"] = style

    # Explicit `in` check so the studio can clear the benchtop with null.
    if "benchtop_material" in updated:
        project["benchtop_material"] = updated["benchtop_material"]

    if "wall" in updated:
        project["wall"] = updated["wall"]
    if "wall_finish" in updated:
        project["wall_finish"] = _clean_wall_finish(updated["wall_finish"])
    if "subtotal" in updated:
        project["subtotal"] = updated["subtotal"]
    if "gst" in updated:
        project["gst"] = updated["gst"]
    if "total_price" in updated:
        project["total_price"] = updated["total_price"]
    if "line_items" in updated:
        project["line_items"] = updated["line_items"]
    
    project["updated_at"] = datetime.utcnow().isoformat() + "Z"
    
    normalized = _normalize_project(project)
    db[quote_id] = normalized
    _save_projects_db(db)
    return {"status": "updated", "project": normalized}


@app.post("/api/projects/{quote_id}/deposit")
def pay_project_deposit(quote_id: str):
    """Processes customer online slot deposit reservation (RM250)."""
    db = _load_projects_db()
    if quote_id not in db:
        raise HTTPException(status_code=404, detail="Project not found")
    project = db[quote_id]
    project["deposit_paid"] = 250.0
    project["deposit_paid_at"] = datetime.utcnow().isoformat() + "Z"
    project["updated_at"] = datetime.utcnow().isoformat() + "Z"
    db[quote_id] = project
    _save_projects_db(db)
    return {"status": "success", "deposit_paid": 250.0, "message": "Manufacturing queue reserved"}


def _require_admin(supplied: str | None) -> None:
    if not catalog_lib.admin_key_ok(supplied):
        raise HTTPException(
            status_code=401,
            detail="Changing the catalogue needs the admin key.",
        )


@app.get("/api/catalog")
def get_catalog(version: int | None = None):
    """The catalogue: modules and prices, pricing rules, finishes, benchtops,
    labour, tax and the layout generator's sizes. ``?version=N`` returns an
    earlier version (the one a quote was priced with)."""
    found = catalogs.current() if version is None else catalogs.get_version(version)
    if found is None:
        raise HTTPException(status_code=404, detail=f"Catalogue version {version} not found")
    doc = found.api_dict()
    doc["requires_admin_key"] = bool(os.environ.get("CATALOG_ADMIN_KEY"))
    return doc


@app.get("/api/catalog/versions")
def list_catalog_versions():
    return {"current": catalogs.current().version, "versions": catalogs.versions()}


@app.put("/api/catalog")
def update_catalog(
    payload: dict[str, Any],
    x_admin_key: str | None = Header(default=None),
):
    """Saves a new catalogue version.

    Send the whole catalogue document (as GET returns it, without the derived
    flat maps) plus ``base_version``, the version you started from: a 409 says
    someone else saved in between. The older partial form
    (``{"cabinets": {type: price}, "styles": {...}, "labour_rate_per_cabinet": n}``)
    still works.
    """
    _require_admin(x_admin_key)
    try:
        if "modules" in payload or "families" in payload:
            document = {k: v for k, v in payload.items() if k != "base_version"}
            new = catalogs.save(document, payload.get("base_version"))
        else:
            new = catalogs.update_legacy(payload)
    except catalog_lib.CatalogConflict as err:
        raise HTTPException(status_code=409, detail=str(err))
    except catalog_lib.ValidationError as err:
        raise HTTPException(
            status_code=422,
            detail=[
                {"where": ".".join(str(p) for p in e["loc"]), "message": e["msg"]}
                for e in err.errors()
            ],
        )
    return {"status": "catalog_updated", "catalog": new.api_dict()}


@app.get("/api/export/{quote_id}/dxf")
def export_dxf(quote_id: str):
    """Exports project geometry to AutoCAD R12 ASCII DXF for factory cutting."""
    db = _load_projects_db()
    project = db.get(quote_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    dxf_content = generate_dxf(project)
    return Response(
        content=dxf_content,
        media_type="application/dxf",
        headers={
            "Content-Disposition": f'attachment; filename="{quote_id}.dxf"',
        },
    )


@app.get("/api/export/{quote_id}/cutlist")
def export_cutlist(quote_id: str):
    """Exports CNC precision cutting schedule CSV for factory nesting & beam saws."""
    db = _load_projects_db()
    project = db.get(quote_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    cutlist_csv = generate_cutlist_csv(project)
    return Response(
        content=cutlist_csv,
        media_type="text/csv",
        headers={
            "Content-Disposition": f'attachment; filename="{quote_id}_cutting_schedule.csv"',
        },
    )


@app.get("/pdf/{quote_id}")
def get_pdf(quote_id: str):
    path = _pdf_store.get(quote_id)
    if not path or not os.path.exists(path):
        # _pdf_store is in-memory, so after a restart fall back to the stored
        # path and then to the on-disk proposal folder.
        db = _load_projects_db()
        project = db.get(quote_id) or {}
        stored = project.get("pdf_path")
        on_disk = os.path.join(PDF_DIR, f"{quote_id}.pdf")

        if stored and os.path.exists(stored):
            path = stored
        elif os.path.exists(on_disk):
            path = on_disk
        else:
            raise HTTPException(status_code=404, detail="PDF not found")
    return FileResponse(
        path,
        media_type="application/pdf",
        filename=f"{quote_id}.pdf",
    )


# ─── PDF Generation ──────────────────────────────────────────────────────────

_SCENE_OPTIONS = {
    "doors": {"slab", "shaker", "raised"},
    "backsplash": {"none", "subway", "hex"},
    "mood": {"day", "evening"},
}


_COLOUR = re.compile(r"^#[0-9a-fA-F]{6}$")


def _clean_wall_finish(raw: Any) -> dict[str, Any] | None:
    """The wall finish as priced and drawn: its kind, the area in m² (to the
    hundredth, as priced) and, for paint, its colour. Anything else is dropped."""
    if not isinstance(raw, dict):
        return None
    kind = raw.get("kind")
    if not isinstance(kind, str) or not kind or len(kind) > 40:
        return None
    try:
        area = round(float(raw.get("area_m2") or 0), 2)
    except (TypeError, ValueError):
        return None
    if not (0 < area <= 1000):
        return None
    out: dict[str, Any] = {"kind": kind, "area_m2": area}
    colour = raw.get("colour")
    if isinstance(colour, str) and _COLOUR.match(colour):
        out["colour"] = colour.lower()
    return out


def _clean_scene(scene: dict[str, Any] | None) -> dict[str, Any]:
    """The parts of a design's look the server knows, with nothing else kept."""
    if not isinstance(scene, dict):
        return {}
    out: dict[str, Any] = {}
    for key, allowed in _SCENE_OPTIONS.items():
        if scene.get(key) in allowed:
            out[key] = scene[key]
    for key in ("decor", "room"):
        if isinstance(scene.get(key), bool):
            out[key] = scene[key]
    return out


def _scene_note(scene: dict[str, Any] | None) -> str:
    """What in the pictures is not part of the quote (printed under them)."""
    scene = _clean_scene(scene)
    shown = []
    if scene.get("decor", False):
        shown.append("The decor (plates, plants, jars and similar)")
    if scene.get("backsplash", "none") != "none":
        shown.append("the backsplash tile" if shown else "The backsplash tile")
    note = ""
    if shown:
        note = (" and ".join(shown) + (" shown are" if len(shown) > 1 else " shown is")
                + " not part of this quote.")
    if scene.get("doors", "slab") != "slab":
        note += " The door style shown is for illustration."
    if scene.get("room", False):
        note += " The room around the kitchen shown is for illustration."
    return note.strip()


def _pdf_pictures(paths: list[str]) -> list[RLImage]:
    """The design pictures sized to share one row of the page (170 mm wide):
    one fills it, two sit side by side. A file that can't be read is skipped."""
    paths = paths[:2]
    width = 170 * mm / max(len(paths), 1) - 2 * mm
    cells = []
    for path in paths:
        try:
            w, h = ImageReader(path).getSize()
        except Exception:
            continue
        height = width * h / w
        if height > 95 * mm:  # a very tall picture: fit the height instead
            height = 95 * mm
            width_here = height * w / h
        else:
            width_here = width
        cells.append(RLImage(path, width=width_here, height=height))
    return cells


def _generate_pdf(
    quote_id: str,
    request: QuoteRequest,
    line_items: list[LineItem],
    subtotal: float,
    gst: float,
    total_price: float,
    catalog: "catalog_lib.Catalog | None" = None,
    pictures: list[str] | None = None,
    scene: dict[str, Any] | None = None,
    wall_photo_kept: bool = False,
) -> str:
    catalog = catalog or _catalog_for(request)
    # Proposals used to land in the OS temp directory, so every signed PDF was
    # gone after a cleanup or reboot and /pdf/<id> answered 404 forever. Keep
    # them beside the project database instead.
    os.makedirs(PDF_DIR, exist_ok=True)
    path = os.path.join(PDF_DIR, f"{quote_id}.pdf")

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "title",
        parent=styles["Title"],
        fontSize=20,
        spaceAfter=4,
        textColor=colors.HexColor("#1a1a2e"),
    )
    sub_style = ParagraphStyle(
        "sub",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#555577"),
        spaceAfter=12,
    )

    doc = SimpleDocTemplate(
        path,
        pagesize=A4,
        rightMargin=20 * mm,
        leftMargin=20 * mm,
        topMargin=20 * mm,
        bottomMargin=20 * mm,
    )

    story = []

    story.append(Paragraph("Kitchen Cabinet Quotation & Agreement", title_style))
    story.append(Paragraph(
        f"Quote ID: {quote_id} &nbsp;|&nbsp; "
        f"Salesperson: {request.salesperson_id} &nbsp;|&nbsp; "
        f"Date: {datetime.utcnow().strftime('%d %b %Y')}",
        sub_style,
    ))

    # Client & Project Metadata Box
    client_name_str = request.client_name or "Client Walk-in"
    client_contact = f"{request.client_phone or ''} {request.client_email or ''}".strip() or "On-site Consultation"
    style_option = catalog.style_options.get(request.style_archetype)
    style_label = style_option.name if style_option else "Japandi Natural"
    deposit_str = f"Deposit: RM{request.deposit_paid:,.2f} (Slot Locked)" if request.deposit_paid > 0 else "Quotation Only"

    w = request.wall
    meta_info = [
        [
            Paragraph(f"<b>Client:</b> {client_name_str} ({client_contact})", styles["Normal"]),
            Paragraph(f"<b>Style Archetype:</b> {style_label}", styles["Normal"])
        ],
        [
            Paragraph(f"<b>Wall:</b> {w.width_mm:.0f}mm W × {w.height_mm:.0f}mm H × {w.depth_mm:.0f}mm D", styles["Normal"]),
            Paragraph(f"<b>Slot Commitment:</b> <font color='#ff8c42'><b>{deposit_str}</b></font>", styles["Normal"])
        ]
    ]
    meta_table = Table(meta_info, colWidths=[95 * mm, 75 * mm])
    meta_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f8fafc")),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 6 * mm))

    # The design, as pictures: one or two side by side, each as wide as fits.
    picture_cells = _pdf_pictures(pictures or [])
    if picture_cells:
        story.append(Paragraph("<b>Your design</b>", styles["Normal"]))
        story.append(Spacer(1, 2 * mm))
        gallery = Table([picture_cells], colWidths=[170 * mm / len(picture_cells)] * len(picture_cells))
        gallery.setStyle(TableStyle([
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 2 * mm),
            ("TOPPADDING", (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        story.append(gallery)
        story.append(Paragraph(
            "<font size=8 color='#555577'>Pictures show the design. Colours and finishes may look slightly "
            f"different from the real materials. {html.escape(_scene_note(scene))}</font>",
            styles["Normal"],
        ))
    story.append(Spacer(1, 6 * mm))

    # Line items table
    table_data = [["Description", "Qty", "Unit Price", "Total"]]
    for li in line_items:
        sign = "-" if li.total < 0 else ""
        table_data.append([
            li.description,
            str(li.qty),
            f"RM{abs(li.unit_price):,.2f}",
            f"{sign}RM{abs(li.total):,.2f}",
        ])

    # Subtotal / SST / Total rows
    table_data += [
        ["", "", "Subtotal", f"RM{subtotal:,.2f}"],
        ["", "", f"{catalog.tax.label} ({catalog.tax.rate * 100:g}%)", f"RM{gst:,.2f}"],
        ["", "", "TOTAL (incl. SST)", f"RM{total_price:,.2f}"],
    ]

    col_widths = [95 * mm, 20 * mm, 40 * mm, 35 * mm]
    tbl = Table(table_data, colWidths=col_widths)
    tbl.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1a1a2e")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 11),
        ("ROWBACKGROUNDS", (0, 1), (-1, -4), [colors.white, colors.HexColor("#f5f5fa")]),
        ("FONTNAME", (0, -3), (-1, -1), "Helvetica-Bold"),
        ("TEXTCOLOR", (0, -1), (-1, -1), colors.HexColor("#ff8c42")),
        ("FONTSIZE", (0, -1), (-1, -1), 12),
        ("LINEABOVE", (0, -3), (-1, -3), 1, colors.HexColor("#ccccdd")),
        ("LINEBELOW", (0, -1), (-1, -1), 2, colors.HexColor("#1a1a2e")),
        ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (0, -1), 8),
        ("GRID", (0, 0), (-1, -4), 0.3, colors.HexColor("#ddddee")),
    ]))
    story.append(tbl)

    story.append(Spacer(1, 8 * mm))

    # Client Digital Signature Box
    sig_image_widget = None
    if request.signature_base64:
        try:
            sig_raw = base64.b64decode(request.signature_base64)
            sig_tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            sig_tmp.write(sig_raw)
            sig_tmp.close()
            sig_image_widget = RLImage(sig_tmp.name, width=55 * mm, height=20 * mm)
        except Exception:
            sig_image_widget = None

    sig_data = [
        [
            Paragraph(f"<b>Client Acceptance:</b> {client_name_str}<br/><font color='#555555'>{deposit_str}</font>", styles["Normal"]),
            Paragraph(f"<b>Consultant Verification:</b> {request.salesperson_id}<br/><font color='#555555'>Authorised Design Consultant</font>", styles["Normal"]),
        ],
        [
            sig_image_widget if sig_image_widget else Paragraph("<br/><font color='#888888'>[Digitally Signed On Screen]</font>", styles["Normal"]),
            Paragraph("<br/><font color='#888888'>[System Verified & Logged]</font>", styles["Normal"]),
        ],
        [
            Paragraph("____________________________<br/>Client Signature & Date", styles["Normal"]),
            Paragraph("____________________________<br/>Representative Signature", styles["Normal"]),
        ]
    ]
    sig_table = Table(sig_data, colWidths=[95 * mm, 75 * mm])
    sig_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(sig_table)

    story.append(Spacer(1, 6 * mm))
    story.append(Paragraph(
        "This proposal locks in material pricing and reserves manufacturing queue priority for 30 days. All prices in MYR including SST.",
        styles["Normal"],
    ))
    if wall_photo_kept:
        story.append(Spacer(1, 2 * mm))
        story.append(Paragraph(
            "A photo of your wall was kept on our office server to help us measure "
            "more accurately. It is never shared, and we delete it whenever you ask.",
            styles["Normal"],
        ))

    doc.build(story)
    return path


# ─── Static Studio Workbench & Customer 3D Portal Mounts ────────────────────
STUDIO_DIR = os.path.join(os.path.dirname(__file__), "static", "studio")
os.makedirs(STUDIO_DIR, exist_ok=True)
app.mount("/studio", StaticFiles(directory=STUDIO_DIR, html=True), name="studio")

PORTAL_DIR = os.path.join(os.path.dirname(__file__), "static", "portal")
os.makedirs(PORTAL_DIR, exist_ok=True)
app.mount("/portal", StaticFiles(directory=PORTAL_DIR, html=True), name="portal")

# The sales app in a browser (Flutter web build): tool/build_web.sh or
# tool/build_web.ps1 writes it here. Same server, so no CORS or address setup.
SALES_DIR = os.path.join(os.path.dirname(__file__), "static", "sales")
os.makedirs(SALES_DIR, exist_ok=True)
app.mount("/sales", StaticFiles(directory=SALES_DIR, html=True), name="sales")

# ─── Device setup (trust the office server, once per tablet) ────────────────

@app.get("/setup", response_class=HTMLResponse)
def device_setup(request: Request):
    """Page a tablet opens once (over http) to trust the https server."""
    if office_https is None:
        return HTMLResponse(
            "<p>HTTPS isn't available: run <code>pip install -r requirements.txt</code> "
            "on the office computer and restart the server.</p>",
            status_code=503,
        )
    certs = office_https.ensure_certificates()
    return office_https.setup_page(
        host=request.url.hostname or "localhost",
        http_port=request.url.port or 80,
        https_port=app.state.https_port,
        fingerprint=certs.ca_fingerprint,
    )


@app.get("/setup/{filename}")
def device_setup_certificate(filename: str):
    """The office CA certificate (public part only) for tablets to install."""
    if office_https is None or filename != office_https.CA_DOWNLOAD_NAME:
        raise HTTPException(status_code=404, detail="Not found")
    certs = office_https.ensure_certificates()
    return Response(
        content=certs.ca_der,
        media_type="application/x-x509-ca-cert",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.get("/view/{quote_id}")
def view_customer_proposal(quote_id: str):
    """Shareable lightweight client-facing 3D proposal portal."""
    return RedirectResponse(url=f"/portal/?id={quote_id}")

@app.get("/download/apk")
def download_mobile_apk():
    """Download the compiled mobile APK directly to phone or browser."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    apk_release = os.path.join(base_dir, "build", "app", "outputs", "flutter-apk", "app-release.apk")
    apk_debug = os.path.join(base_dir, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
    target = apk_release if os.path.exists(apk_release) else apk_debug
    if os.path.exists(target):
        return FileResponse(target, filename="StaticTrace.apk", media_type="application/vnd.android.package-archive")
    raise HTTPException(status_code=404, detail="APK build not found")

@app.get("/")
def root_redirect():
    return RedirectResponse(url="/studio")


# ─── Dev runner ──────────────────────────────────────────────────────────────

HTTP_PORT = 8000
HTTPS_PORT = 8443


async def _serve_all(servers: list[uvicorn.Server]) -> None:
    import asyncio

    await asyncio.gather(*(server.serve() for server in servers))


def _print_addresses(https_running: bool) -> None:
    ip = office_https.primary_lan_ip() if office_https else None
    host = ip or "localhost"
    print("\nSS Love office server")
    if https_running:
        print(f"  Sales app (browser):    https://{host}:{HTTPS_PORT}/sales/")
        print(f"  Set up a tablet once:   http://{host}:{HTTP_PORT}/setup")
    print(f"  Android app, Studio:    http://{host}:{HTTP_PORT}")
    if not ip:
        print("  (No Wi-Fi/LAN address found: only this computer can connect.)")
    print()


def serve(https: bool = True) -> None:
    """http on 8000 (Android app, Studio, setup page) and, when possible,
    https on 8443 (the sales app in a browser, so the camera works)."""
    import asyncio

    servers = [uvicorn.Server(uvicorn.Config(app, host="0.0.0.0", port=HTTP_PORT))]
    if https and office_https is None:
        print("HTTPS is off: run `pip install -r requirements.txt` to turn it on.")
        https = False
    if https:
        certs = office_https.ensure_certificates()
        app.state.https_port = HTTPS_PORT
        servers.append(
            uvicorn.Server(
                uvicorn.Config(
                    app,
                    host="0.0.0.0",
                    port=HTTPS_PORT,
                    ssl_certfile=str(certs.server_cert),
                    ssl_keyfile=str(certs.server_key),
                )
            )
        )
    _print_addresses(https_running=https)
    try:
        asyncio.run(_serve_all(servers))
    except KeyboardInterrupt:
        # Ctrl+C: both servers have already shut down cleanly.
        pass
    print("Server stopped.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="SS Love office server")
    parser.add_argument(
        "--dev",
        action="store_true",
        help="reload on code changes (http only, port 8000)",
    )
    parser.add_argument("--no-https", action="store_true", help="http only")
    args = parser.parse_args()
    if args.dev:
        uvicorn.run("main:app", host="0.0.0.0", port=HTTP_PORT, reload=True)
    else:
        serve(https=not args.no_https)
