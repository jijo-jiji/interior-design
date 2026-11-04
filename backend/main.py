"""
Static Trace — FastAPI Backend
Handles pricing, PDF generation, and CRM lead logging.
The Flutter app calls POST /quote when the salesperson finalises a layout.
"""

from __future__ import annotations

import io
import json
import uuid
from datetime import datetime
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
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
import tempfile
import base64

try:
    from backend.dxf_exporter import generate_dxf
    from backend.cutlist_generator import generate_cutlist_csv
except ImportError:
    from dxf_exporter import generate_dxf
    from cutlist_generator import generate_cutlist_csv

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

# ─── Pricing table (AUD, mock values) ────────────────────────────────────────

CABINET_PRICES: dict[str, float] = {
    "base_800":   420.00,
    "base_600":   340.00,
    "wall_600":   280.00,
    "tall_600":   620.00,
    "corner_900": 580.00,
}

OBSTACLE_ALLOWANCES: dict[str, float] = {
    "window": -50.00,   # reduces labour slightly
    "door":   -80.00,
}

LABOUR_RATE_PER_CABINET = 120.00
GST_RATE = 0.10  # 10%

STYLE_MULTIPLIERS: dict[str, float] = {
    "japandi": 1.00,
    "minimalist": 1.08,
    "nordic": 1.12,
    "industrial": 1.18,
}

STYLE_NAMES: dict[str, str] = {
    "japandi": "Japandi Natural",
    "minimalist": "Modern Minimalist",
    "nordic": "Warm Nordic",
    "industrial": "Industrial Luxe",
}

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

class PlacedCabinet(BaseModel):
    cabinet_type: str
    label: str
    width_mm: float
    height_mm: float
    depth_mm: float
    x_mm: float = 0.0
    y_mm: float = 0.0
    z_mm: float = 0.0
    wall_index: int = 0
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))

class QuoteRequest(BaseModel):
    quote_id: str | None = None
    wall: WallSpec
    obstacles: list[ObstacleSpec] = []
    placed_cabinets: list[PlacedCabinet] = []
    salesperson_id: str = "demo_agent_01"
    style_archetype: str = "japandi"
    client_name: str | None = None
    client_phone: str | None = None
    client_email: str | None = None
    deposit_paid: float = 0.0
    signature_base64: str | None = None

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


@app.post("/quote", response_model=QuoteResponse)
def create_quote(request: QuoteRequest):
    quote_id = request.quote_id if (request.quote_id and request.quote_id.startswith("QT-")) else f"QT-{uuid.uuid4().hex[:8].upper()}"

    # Build line items
    line_items: list[LineItem] = []

    # Group cabinets by type
    from collections import Counter
    cab_counts = Counter(c.cabinet_type for c in request.placed_cabinets)
    mult = STYLE_MULTIPLIERS.get(request.style_archetype, 1.00)
    style_label = STYLE_NAMES.get(request.style_archetype, "Japandi Natural")

    for cab_type, qty in cab_counts.items():
        base_unit = CABINET_PRICES.get(cab_type, 300.00)
        unit = round(base_unit * mult, 2)
        line_items.append(LineItem(
            description=f"Cabinet — {cab_type.replace('_', ' ').title()} ({style_label})",
            qty=qty,
            unit_price=unit,
            total=round(unit * qty, 2),
        ))

    # Labour
    total_cabs = sum(cab_counts.values())
    if total_cabs > 0:
        labour_total = LABOUR_RATE_PER_CABINET * total_cabs
        line_items.append(LineItem(
            description="Installation Labour",
            qty=total_cabs,
            unit_price=LABOUR_RATE_PER_CABINET,
            total=labour_total,
        ))

    # Obstacle allowances
    for obs in request.obstacles:
        allowance = OBSTACLE_ALLOWANCES.get(obs.type, 0)
        if allowance != 0:
            line_items.append(LineItem(
                description=f"{obs.type.title()} cutout allowance",
                qty=1,
                unit_price=allowance,
                total=allowance,
            ))

    subtotal = sum(li.total for li in line_items)
    gst = round(subtotal * GST_RATE, 2)
    total_price = round(subtotal + gst, 2)

    # Generate PDF
    pdf_path = _generate_pdf(
        quote_id=quote_id,
        request=request,
        line_items=line_items,
        subtotal=subtotal,
        gst=gst,
        total_price=total_price,
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
_pdf_store: dict[str, str] = {}


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

    # Normalize cabinets list
    raw_cabs = p.get("placed_cabinets") or p.get("cabinets") or []
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
            height_m = 2.1 if cab_type == "tall_600" else (0.72 if cab_type == "wall_600" else 0.85)

        depth_m = c.get("depth")
        if depth_m is None and "depth_mm" in c:
            depth_m = float(c["depth_mm"]) / 1000.0
        if depth_m is None:
            depth_m = 0.35 if cab_type == "wall_600" else 0.6

        # Coordinate x in meters
        x_m = c.get("x")
        raw_x_mm = c.get("x_mm")
        if x_m is None:
            if raw_x_mm is not None:
                val = float(raw_x_mm)
                # If negative (e.g. Flutter relative to wall center), translate to left offset
                x_m = (val + 1800.0) / 1000.0 if val < 0 else val / 1000.0
            elif "distance_from_left_mm" in c:
                x_m = float(c["distance_from_left_mm"]) / 1000.0
            else:
                x_m = 0.2 + idx * 0.7

        x_m = max(0.05, round(x_m, 3))
        x_mm = round(x_m * 1000.0)

        normalized_cabs.append({
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
            "x_mm": raw_x_mm if raw_x_mm is not None else x_mm,
            "distance_from_left_mm": x_mm,
            "isWallMounted": cab_type == "wall_600",
        })

        normalized_placed.append({
            "id": cab_id,
            "cabinet_type": cab_type,
            "label": c.get("label") or f"{cab_type.replace('_', ' ').title()}",
            "width_mm": round(width_m * 1000.0),
            "height_mm": round(height_m * 1000.0),
            "depth_mm": round(depth_m * 1000.0),
            "x_mm": raw_x_mm if raw_x_mm is not None else x_mm,
            "y_mm": c.get("y_mm", 0.0),
            "z_mm": c.get("z_mm", 0.0),
            "wall_index": c.get("wall_index", 0),
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

    if "wall" in updated:
        project["wall"] = updated["wall"]
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
    """Processes customer online slot deposit reservation ($250)."""
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


@app.get("/api/catalog")
def get_catalog():
    """Returns master cabinet pricing table, style multipliers, and labor rates."""
    return {
        "cabinets": CABINET_PRICES,
        "styles": STYLE_MULTIPLIERS,
        "style_names": STYLE_NAMES,
        "labour_rate_per_cabinet": LABOUR_RATE_PER_CABINET,
        "gst_rate": GST_RATE,
    }


@app.put("/api/catalog")
def update_catalog(payload: dict[str, Any]):
    """Updates pricing matrix rules and material multipliers."""
    global LABOUR_RATE_PER_CABINET
    if "cabinets" in payload and isinstance(payload["cabinets"], dict):
        for k, v in payload["cabinets"].items():
            if k in CABINET_PRICES:
                CABINET_PRICES[k] = float(v)
    if "styles" in payload and isinstance(payload["styles"], dict):
        for k, v in payload["styles"].items():
            if k in STYLE_MULTIPLIERS:
                STYLE_MULTIPLIERS[k] = float(v)
    if "labour_rate_per_cabinet" in payload:
        LABOUR_RATE_PER_CABINET = float(payload["labour_rate_per_cabinet"])
    return {"status": "catalog_updated", "catalog": get_catalog()}


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
        db = _load_projects_db()
        project = db.get(quote_id)
        if project and "pdf_path" in project and os.path.exists(project["pdf_path"]):
            path = project["pdf_path"]
        else:
            raise HTTPException(status_code=404, detail="PDF not found")
    return FileResponse(
        path,
        media_type="application/pdf",
        filename=f"{quote_id}.pdf",
    )


# ─── PDF Generation ──────────────────────────────────────────────────────────

def _generate_pdf(
    quote_id: str,
    request: QuoteRequest,
    line_items: list[LineItem],
    subtotal: float,
    gst: float,
    total_price: float,
) -> str:
    tmp = tempfile.NamedTemporaryFile(
        suffix=".pdf", delete=False, prefix=f"{quote_id}_"
    )
    path = tmp.name
    tmp.close()

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
    style_label = STYLE_NAMES.get(request.style_archetype, "Japandi Natural")
    deposit_str = f"Deposit: ${request.deposit_paid:.2f} (Slot Locked)" if request.deposit_paid > 0 else "Quotation Only"

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
    story.append(Spacer(1, 8 * mm))

    # Line items table
    table_data = [["Description", "Qty", "Unit Price", "Total"]]
    for li in line_items:
        sign = "-" if li.total < 0 else ""
        table_data.append([
            li.description,
            str(li.qty),
            f"${abs(li.unit_price):.2f}",
            f"{sign}${abs(li.total):.2f}",
        ])

    # Subtotal / GST / Total rows
    table_data += [
        ["", "", "Subtotal", f"${subtotal:.2f}"],
        ["", "", f"GST ({int(GST_RATE*100)}%)", f"${gst:.2f}"],
        ["", "", "TOTAL (incl. GST)", f"${total_price:.2f}"],
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
        "This proposal locks in material pricing and reserves manufacturing queue priority for 30 days. All prices in AUD including GST.",
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
