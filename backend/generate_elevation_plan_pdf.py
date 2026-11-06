"""
Generates an executive-quality PDF report for:
Dual-Platform Elevation Plan: Mobile Sales Closer & Web Studio Workbench Audit & Implementation Roadmap.
"""

import os
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from reportlab.pdfgen import canvas


class NumberedCanvas(canvas.Canvas):
    """Adds running headers and 'Page X of Y' footers."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#718096"))

        # Running header (pages 2+)
        if self._pageNumber > 1:
            self.drawString(
                18 * mm,
                297 * mm - 13 * mm,
                "Static Trace — Dual-Platform Elevation Plan & Architecture Audit"
            )
            self.setStrokeColor(colors.HexColor("#CBD5E0"))
            self.setLineWidth(0.5)
            self.line(18 * mm, 297 * mm - 15 * mm, 210 * mm - 18 * mm, 297 * mm - 15 * mm)

        # Running footer
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(210 * mm - 18 * mm, 12 * mm, page_str)
        self.drawString(
            18 * mm,
            12 * mm,
            "Confidential & Proprietary — Prepared for Product Architecture & Engineering Review"
        )
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.5)
        self.line(18 * mm, 15 * mm, 210 * mm - 18 * mm, 15 * mm)

        self.restoreState()


def build_pdf(filename: str):
    doc = SimpleDocTemplate(
        filename,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=20 * mm,
        bottomMargin=20 * mm,
    )

    styles = getSampleStyleSheet()

    # Brand Palette
    PRIMARY = colors.HexColor("#0F172A")    # Deep Slate Navy
    SECONDARY = colors.HexColor("#1E293B")  # Slate 800
    ACCENT = colors.HexColor("#D97706")     # Warm Amber Accent
    ACCENT_LIGHT = colors.HexColor("#FEF3C7")
    CYAN = colors.HexColor("#0891B2")       # Tech Cyan
    CYAN_LIGHT = colors.HexColor("#ECFEFF")
    GREEN = colors.HexColor("#16A34A")
    GREEN_LIGHT = colors.HexColor("#DCFCE7")
    RED = colors.HexColor("#DC2626")
    RED_LIGHT = colors.HexColor("#FEE2E2")
    TEXT_DARK = colors.HexColor("#1E293B")
    TEXT_MUTED = colors.HexColor("#64748B")
    BORDER_COLOR = colors.HexColor("#E2E8F0")
    BG_LIGHT = colors.HexColor("#F8FAFC")

    # Typography Styles
    title_style = ParagraphStyle(
        "DocTitle",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=20,
        leading=24,
        textColor=PRIMARY,
        spaceAfter=4,
    )

    subtitle_style = ParagraphStyle(
        "DocSubtitle",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=10,
        leading=14,
        textColor=TEXT_MUTED,
        spaceAfter=12,
    )

    h1_style = ParagraphStyle(
        "H1",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=13,
        leading=17,
        textColor=PRIMARY,
        spaceBefore=12,
        spaceAfter=6,
    )

    h2_style = ParagraphStyle(
        "H2",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=10.5,
        leading=14,
        textColor=SECONDARY,
        spaceBefore=8,
        spaceAfter=4,
    )

    body_style = ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=8.5,
        leading=12.5,
        textColor=TEXT_DARK,
        spaceAfter=5,
    )

    bullet_style = ParagraphStyle(
        "Bullet",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=8.2,
        leading=11.5,
        textColor=TEXT_DARK,
        leftIndent=12,
        spaceAfter=3,
    )

    table_header_style = ParagraphStyle(
        "TH",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.8,
        leading=10,
        textColor=colors.white,
    )

    table_cell_style = ParagraphStyle(
        "TD",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=7.2,
        leading=9.5,
        textColor=TEXT_DARK,
    )

    table_cell_bold = ParagraphStyle(
        "TDBold",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.2,
        leading=9.5,
        textColor=PRIMARY,
    )

    table_cell_bad = ParagraphStyle(
        "TDBad",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.2,
        leading=9.5,
        textColor=RED,
    )

    table_cell_good = ParagraphStyle(
        "TDGood",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.2,
        leading=9.5,
        textColor=GREEN,
    )

    story = []

    # ── HEADER BLOCK ──────────────────────────────────────────────────────────
    story.append(Paragraph("DUAL-PLATFORM ELEVATION PLAN", title_style))
    story.append(Paragraph(
        "Mobile Sales Closer & Web Studio Workbench: Comprehensive Flaw Analysis, UX Modernization & Implementation Roadmap",
        subtitle_style
    ))

    # Meta banner table
    meta_data = [
        [
            Paragraph("<b>DOCUMENT CLASSIFICATION:</b> Engineering Plan", table_cell_style),
            Paragraph("<b>VERSION:</b> 2.0 (Post-Test Review)", table_cell_style),
            Paragraph("<b>TARGET OS:</b> Flutter (Android/iOS) + Web (FastAPI/Three.js)", table_cell_style),
            Paragraph("<b>DATE:</b> September 2026", table_cell_style),
        ]
    ]
    meta_table = Table(meta_data, colWidths=[45 * mm, 40 * mm, 55 * mm, 34 * mm])
    meta_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), BG_LIGHT),
        ("BOX", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 8))

    # ── SECTION 1: EXECUTIVE AUDIT SUMMARY ──────────────────────────────────
    story.append(Paragraph("1. Executive Summary & Problem Diagnosis", h1_style))
    story.append(Paragraph(
        "Following an end-to-end audit of our dual-platform architecture (Mobile Sales Closer + Web Studio Companion), "
        "we evaluated the commercial viability of the workflow against premier industry standards (Coohom, 2020 Design, Cabinet Vision). "
        "While the prototype successfully proves 15-minute consultation closing on a single straight wall, <b>14 critical architectural, "
        "spatial, and UX flaws prevent it from operating as an enterprise-grade commercial product</b>.",
        body_style
    ))

    story.append(Paragraph(
        "The core structural disconnect lies in the <b>unidirectional data flow and functional asymmetry</b>: "
        "the mobile app is touch-first but lacks project history, multi-wall support, and offline persistence; meanwhile, "
        "the Web Studio Workbench is strictly passive (view-only), preventing back-office estimators from modifying cabinet layouts, "
        "fixing on-site mistakes, or sending approved revisions back to field reps.",
        body_style
    ))

    story.append(Spacer(1, 6))

    # ── SECTION 2: THE 14-POINT FLAW & REMEDIATION MATRIX ────────────────────
    story.append(Paragraph("2. Comprehensive Flaw Audit & Target Solution Matrix", h1_style))

    matrix_headers = [
        Paragraph("<b>#</b>", table_header_style),
        Paragraph("<b>Area</b>", table_header_style),
        Paragraph("<b>Critical Flaw Identified</b>", table_header_style),
        Paragraph("<b>Operational & Closing Impact</b>", table_header_style),
        Paragraph("<b>Target Architectural Remedy</b>", table_header_style),
    ]

    matrix_rows = [
        matrix_headers,
        [
            Paragraph("1", table_cell_bold),
            Paragraph("Mobile", table_cell_bold),
            Paragraph("<b>No Pipeline / Drafts Screen</b>: Reps cannot view past quotes, reopen drafts, or search clients.", table_cell_bad),
            Paragraph("Loss of sales continuity; cannot resume consultations across home visits.", table_cell_style),
            Paragraph("<b>Consultations Hub</b>: Mobile CRM screen with search, draft filters, and 1-tap reload.", table_cell_good),
        ],
        [
            Paragraph("2", table_cell_bold),
            Paragraph("Mobile", table_cell_bold),
            Paragraph("<b>Blank Wall Blocker</b>: `trace_screen.dart` disables 'Generate 3D' if obstacles list is empty.", table_cell_bad),
            Paragraph("Reps cannot generate 3D for a plain wall without creating dummy windows/doors.", table_cell_style),
            Paragraph("Make obstacles optional; allow instantaneous 3D generation for plain walls.", table_cell_good),
        ],
        [
            Paragraph("3", table_cell_bold),
            Paragraph("Mobile", table_cell_bold),
            Paragraph("<b>Pseudo Offline Storage</b>: Claims to save locally on error, but writes no data to disk.", table_cell_bad),
            Paragraph("If 4G/Wi-Fi drops on-site, signed quotes and finger signatures are permanently lost.", table_cell_style),
            Paragraph("<b>Local Queue</b>: `shared_preferences`/JSON draft outbox with auto-sync on reconnect.", table_cell_good),
        ],
        [
            Paragraph("4", table_cell_bold),
            Paragraph("3D Engine", table_cell_bold),
            Paragraph("<b>1D Rail vs. Multi-Wall</b>: Template generator offers L-Shape & Galley, but 3D engine only renders 1 straight wall.", table_cell_bad),
            Paragraph("Reps cannot close L-shaped kitchens (>60% of modern residential homes).", table_cell_style),
            Paragraph("<b>Multi-Wall 3D Rail</b>: Extend Three.js to render corner walls ($90^\\circ$) with corner snapping.", table_cell_good),
        ],
        [
            Paragraph("5", table_cell_bold),
            Paragraph("Mobile", table_cell_bold),
            Paragraph("<b>Blueprint Matrix Drift</b>: `InteractiveViewer` pan/zoom does not transform Pin A & B coordinates.", table_cell_bad),
            Paragraph("Pinch-zooming into blueprints misaligns calibration pins and corrupts scale ratio.", table_cell_style),
            Paragraph("Bind calibration pins to normalized image matrix space instead of screen coords.", table_cell_good),
        ],
        [
            Paragraph("6", table_cell_bold),
            Paragraph("Mobile", table_cell_bold),
            Paragraph("<b>Mock WhatsApp & Sales ID</b>: Sales ID hardcoded to 'demo_agent_01'; WhatsApp share is just a snackbar.", table_cell_bad),
            Paragraph("Cannot track sales rep commissions; cannot instantly dispatch link to customer phone.", table_cell_style),
            Paragraph("Rep profile selector + native deep link (`whatsapp://send?phone=...`).", table_cell_good),
        ],
        [
            Paragraph("7", table_cell_bold),
            Paragraph("Web Studio", table_cell_bold),
            Paragraph("<b>Passive / View-Only CAD</b>: Estimators cannot move, snap, add, delete, or resize modules in Studio.", table_cell_bad),
            Paragraph("Back-office designers cannot adjust field layouts without external software.", table_cell_style),
            Paragraph("<b>Interactive CAD Editor</b>: Drag, snap, delete, and insert cabinets directly in Studio.", table_cell_good),
        ],
        [
            Paragraph("8", table_cell_bold),
            Paragraph("Web Studio", table_cell_bold),
            Paragraph("<b>No Revision Save UI</b>: Backend has `PUT /api/projects/{id}`, but Web Studio has no UI to save edits.", table_cell_bad),
            Paragraph("Design modifications cannot be persisted or pushed to factory CNC.", table_cell_style),
            Paragraph("Add 'Save Revisions', 'Override BOQ', and 'Approve Handover' controls.", table_cell_good),
        ],
        [
            Paragraph("9", table_cell_bold),
            Paragraph("Visuals", table_cell_bold),
            Paragraph("<b>Primitive Box Graphics</b>: Flat colored boxes without toe-kicks, benchtops, or hardware handles.", table_cell_bad),
            Paragraph("Lacks emotional design appeal required to close \$15k–\$40k custom renovations.", table_cell_style),
            Paragraph("Continuous beveled countertops, 150mm recessed toe-kicks, and brushed handles.", table_cell_good),
        ],
        [
            Paragraph("10", table_cell_bold),
            Paragraph("API / Sync", table_cell_bold),
            Paragraph("<b>Data Loss on Ingestion</b>: `PlacedCabinet` schema omits `x_mm`, stripping module positions on POST.", table_cell_bad),
            Paragraph("Future reloads and DXF exports collapse all cabinets to $X=0$.", table_cell_style),
            Paragraph("Add `x_mm`, `y_mm`, `z_mm`, and `wall_index` to Pydantic models.", table_cell_good),
        ],
        [
            Paragraph("11", table_cell_bold),
            Paragraph("Sync", table_cell_bold),
            Paragraph("<b>Unidirectional Flow</b>: Mobile pushes to backend, but cannot pull studio adjustments back.", table_cell_bad),
            Paragraph("Field reps cannot see estimator corrections or approved manufacturer discounts.", table_cell_style),
            Paragraph("Bi-directional sync: Mobile can fetch updated project state via `GET /api/projects/{id}`.", table_cell_good),
        ],
        [
            Paragraph("12", table_cell_bold),
            Paragraph("Client UX", table_cell_bold),
            Paragraph("<b>No Shareable 3D Portal</b>: Clients only receive a static PDF; no interactive web model for family review.", table_cell_bad),
            Paragraph("Dampens closing velocity after the rep leaves the customer's living room.", table_cell_style),
            Paragraph("<b>Client 3D Portal</b> (`/view/{quote_id}`): Mobile web 360° spin, style toggle, and deposit link.", table_cell_good),
        ],
        [
            Paragraph("13", table_cell_bold),
            Paragraph("CPQ Engine", table_cell_bold),
            Paragraph("<b>Missing Benchtops & Stone</b>: CPQ prices cabinets and labour, but omits countertop materials.", table_cell_bad),
            Paragraph("Benchtops account for 25%–35% of total project cost, creating massive quote inaccuracies.", table_cell_style),
            Paragraph("Add Benchtop Stone Calculator (Engineered Quartz, Granite, Laminate per linear metre).", table_cell_good),
        ],
        [
            Paragraph("14", table_cell_bold),
            Paragraph("Factory CAD", table_cell_bold),
            Paragraph("<b>2D Wireframe DXF</b>: DXF only contains basic lines without panel cutting lists or CNC nesting layers.", table_cell_bad),
            Paragraph("CNC operators must manually re-draft parts before automated nesting.", table_cell_style),
            Paragraph("Layer-separated DXF with part IDs, carcass labels, and dimensional leaders.", table_cell_good),
        ],
    ]

    col_widths = [8 * mm, 18 * mm, 46 * mm, 46 * mm, 56 * mm]
    matrix_table = Table(matrix_rows, colWidths=col_widths, repeatRows=1)
    matrix_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), PRIMARY),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 3.5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3.5),
        *[("BACKGROUND", (0, i), (-1, i), BG_LIGHT) for i in range(2, len(matrix_rows), 2)],
    ]))

    story.append(matrix_table)
    story.append(PageBreak())

    # ── SECTION 3: DEEP ARCHITECTURAL SOLUTIONS ─────────────────────────────
    story.append(Paragraph("3. Deep Architectural Solutions & Technical Specifications", h1_style))

    # 3.1 Mobile Sales Closer Hub
    story.append(Paragraph("3.1 Mobile Consultation Hub & True Offline Architecture", h2_style))
    story.append(Paragraph(
        "To elevate the mobile app from a single-session demo into a true field sales tool, we replace the single-purpose "
        "intake screen with a dual-tab <b>Consultation Pipeline Hub</b>. Tab 1 houses the 3 room capture engines (Camera Wall Trace, "
        "2D Blueprint Calibrate, and 10s Template Dial). Tab 2 displays a real-time list of all active consultations, allowing the rep "
        "to resume work, search by client name, or inspect status badges ('Priority Locked $250', 'Estimate Sent', 'Studio Revised').",
        body_style
    ))
    story.append(Paragraph("• <b>Local Outbox Storage:</b> Quotes, placed cabinet coordinates, and base64 signatures are written to a persistent local JSON outbox using <code>shared_preferences</code> before network transmission. If connectivity fails, the app queues the submission and automatically flushes when Wi-Fi/4G is detected.", bullet_style))
    story.append(Paragraph("• <b>Zero-Obstacle Unblocker:</b> In <code>trace_screen.dart</code>, the check <code>obstacles.isEmpty ? null : _generate3D()</code> is removed. Empty walls immediately render in 3D, accelerating pitches for clean renovation surfaces.", bullet_style))

    story.append(Spacer(1, 4))

    # 3.2 3D Multi-Wall Rail System
    story.append(Paragraph("3.2 Multi-Wall 3D Rail & Continuous Architectural Benchtop", h2_style))
    story.append(Paragraph(
        "Real kitchen sales are dominated by L-shape and U-shape spaces. We upgrade the Three.js scene (<code>assets/3d/index.html</code>) "
        "from a single 1D rail into a <b>Dual-Wall Coordinate System</b>:",
        body_style
    ))
    story.append(Paragraph("• <b>L-Shape Geometry Generation:</b> When <code>shape == 'lShape'</code>, the engine generates Wall 1 (Length $W_1$, aligned along X) and Wall 2 (Return Length $W_2$, rotated $90^\\circ$ and aligned along Z).", bullet_style))
    story.append(Paragraph("• <b>Corner Cabinet Snapping:</b> The <code>corner_900</code> module automatically docks into the intersection $(0, 0, 0)$, anchoring the transition between Wall 1 and Wall 2.", bullet_style))
    story.append(Paragraph("• <b>Continuous Countertops & Kickboards:</b> Instead of each cabinet rendering its own independent worktop block, the engine generates a continuous stone slab spanning the entire placed base cabinet run, complete with 150mm recessed dark toe-kicks.", bullet_style))

    story.append(Spacer(1, 4))

    # 3.3 Interactive Web Studio Workbench 2.0
    story.append(Paragraph("3.3 Interactive Web Studio Workbench 2.0 (Active CAD Editor)", h2_style))
    story.append(Paragraph(
        "The Web Studio companion (<code>backend/static/studio/index.html</code>) is upgraded from a passive viewer into a full "
        "<b>back-office CAD editing station</b>. Senior designers and estimators can:",
        body_style
    ))
    story.append(Paragraph("• <b>Reposition & Snap Modules:</b> Click and drag cabinets along the wall rail using raycasting on desktop browsers, with live collision detection preventing cabinet overlaps.", bullet_style))
    story.append(Paragraph("• <b>Add / Delete / Resize Modules:</b> Add tall units, base drawers, or upper shelving directly from a sidebar palette, or delete misaligned items placed on-site.", bullet_style))
    story.append(Paragraph("• <b>Persistent Revision Control:</b> A 'Save Studio Revisions' action triggers <code>PUT /api/projects/{id}</code>, updating the financial BOQ, regenerating the factory DXF, and flagging the project as 'Studio Revised' for field reps.", bullet_style))

    story.append(Spacer(1, 4))

    # 3.4 Shareable Customer 3D Proposal Portal
    story.append(Paragraph("3.4 Customer Shareable 3D Proposal Portal (`/view/{quote_id}`)", h2_style))
    story.append(Paragraph(
        "Closing in-person is powerful, but final multi-thousand dollar commitments often involve spouses, partners, or financial decision-makers "
        "who were not present. We introduce a public, lightweight web route <code>/view/{quote_id}</code>:",
        body_style
    ))
    story.append(Paragraph("• <b>Mobile-First 360° Visualizer:</b> Loads directly in Safari/Chrome without app installation. Customers can spin the 3D kitchen, toggle finishes (Japandi, Nordic, Minimalist, Industrial), and inspect their exact cabinet inclusions.", bullet_style))
    story.append(Paragraph("• <b>Deposit & Slot Reservation:</b> Includes a direct call-to-action to lock in manufacturing queue priority (RM250 slot reservation via online payment gateway).", bullet_style))

    story.append(Spacer(1, 6))

    # ── SECTION 4: PHASED ROADMAP & TIMELINE ─────────────────────────────────
    story.append(Paragraph("4. Five-Phase Execution Roadmap & Milestones", h1_style))

    roadmap_headers = [
        Paragraph("<b>Phase</b>", table_header_style),
        Paragraph("<b>Focus Domain</b>", table_header_style),
        Paragraph("<b>Key Technical Deliverables</b>", table_header_style),
        Paragraph("<b>Validation Gate</b>", table_header_style),
    ]

    roadmap_rows = [
        roadmap_headers,
        [
            Paragraph("<b>Phase 1</b>", table_cell_bold),
            Paragraph("Mobile Polish & Core Data Integrity", table_cell_bold),
            Paragraph("• Unblock empty wall 3D generation in `trace_screen.dart`<br/>• Mobile Consultation Pipeline Hub (view past quotes)<br/>• Real offline JSON outbox queue (`shared_preferences`)<br/>• Fix `PlacedCabinet` schema in `main.py` to preserve `x_mm`", table_cell_style),
            Paragraph("`flutter test`<br/>`pytest backend/test_studio.py`", table_cell_good),
        ],
        [
            Paragraph("<b>Phase 2</b>", table_cell_bold),
            Paragraph("Multi-Wall 3D & Spatial Realism", table_cell_bold),
            Paragraph("• L-Shape multi-wall rail system in Three.js (`assets/3d/`)<br/>• Corner cabinet (900x900) junction snapping<br/>• Continuous beveled stone countertop generator<br/>• Benchtop stone calculator in `CPQEngine.dart`", table_cell_style),
            Paragraph("L-shape room visual test<br/>CPQ benchtop unit tests", table_cell_good),
        ],
        [
            Paragraph("<b>Phase 3</b>", table_cell_bold),
            Paragraph("Interactive Web Studio Workbench 2.0", table_cell_bold),
            Paragraph("• Interactive cabinet drag, snap, and delete in desktop browser<br/>• Cabinet palette in Web Studio for back-office estimators<br/>• 'Save Revisions' calling `PUT /api/projects/{id}`<br/>• High-fidelity material textures (oak grain, matte slate)", table_cell_style),
            Paragraph("Playwright E2E recording of studio edits & DXF regeneration", table_cell_good),
        ],
        [
            Paragraph("<b>Phase 4</b>", table_cell_bold),
            Paragraph("Customer Shareable 3D Proposal Portal", table_cell_bold),
            Paragraph("• Standalone customer route `/view/{quote_id}`<br/>• Native WhatsApp deep link from mobile app<br/>• Homeowner 360° interactive spin & style toggle<br/>• Online slot deposit payment trigger (RM250)", table_cell_style),
            Paragraph("Mobile browser smoke test & WhatsApp payload verification", table_cell_good),
        ],
        [
            Paragraph("<b>Phase 5</b>", table_cell_bold),
            Paragraph("Precision Factory DXF & Production Nesting", table_cell_bold),
            Paragraph("• AutoCAD Release 12 layered DXF with part IDs<br/>• Automatic dimensional leader lines on elevations<br/>• Itemized cutting schedule export (CSV/Excel)", table_cell_style),
            Paragraph("AutoCAD / LibreCAD import validation & CNC nesting check", table_cell_good),
        ],
    ]

    roadmap_table = Table(roadmap_rows, colWidths=[18 * mm, 38 * mm, 82 * mm, 36 * mm])
    roadmap_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), PRIMARY),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        *[("BACKGROUND", (0, i), (-1, i), BG_LIGHT) for i in range(2, len(roadmap_rows), 2)],
    ]))

    story.append(roadmap_table)
    story.append(Spacer(1, 10))

    # Sign-off box
    signoff_data = [
        [
            Paragraph("<b>Architectural Approval & Sign-Off:</b>", table_cell_bold),
            Paragraph("<b>Status:</b> Ready for Phased Execution", table_cell_style),
        ],
        [
            Paragraph("Prepared by: Antigravity Dual-Platform Engineering Team<br/>Scope: Mobile Sales Closer, Web Studio Companion & Factory CNC Bridge", table_cell_style),
            Paragraph("Recommended Starting Gate: <b>Phase 1 (Mobile Polish & Data Integrity)</b><br/>Target Delivery: Production-Grade Closing Velocity", table_cell_style),
        ]
    ]
    signoff_table = Table(signoff_data, colWidths=[90 * mm, 84 * mm])
    signoff_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), BG_LIGHT),
        ("BOX", (0, 0), (-1, -1), 0.8, ACCENT),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(signoff_table)

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"[SUCCESS] Elevation Plan PDF generated at: {filename}")


if __name__ == "__main__":
    output_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "plan", "Dual_Platform_Elevation_Plan.pdf"))
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    build_pdf(output_path)
