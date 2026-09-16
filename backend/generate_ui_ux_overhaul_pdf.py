"""
Generates an executive-quality PDF report for:
10x UI/UX Overhaul Plan: Mobile App & Web Suite.
"""

import os
import sys
import shutil
from pathlib import Path
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

        if self._pageNumber > 1:
            self.drawString(
                18 * mm,
                297 * mm - 13 * mm,
                "Static Trace — 10x UI/UX Overhaul Plan (Mobile App & Web Suite)"
            )
            self.setStrokeColor(colors.HexColor("#CBD5E0"))
            self.setLineWidth(0.5)
            self.line(18 * mm, 297 * mm - 15 * mm, 210 * mm - 18 * mm, 297 * mm - 15 * mm)

        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(210 * mm - 18 * mm, 12 * mm, page_str)
        self.drawString(
            18 * mm,
            12 * mm,
            "Confidential & Commercial — Prepared for Product Design & Engineering Architecture"
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

    PRIMARY = colors.HexColor("#0F172A")
    SECONDARY = colors.HexColor("#1E293B")
    ACCENT = colors.HexColor("#D97706")
    ACCENT_LIGHT = colors.HexColor("#FEF3C7")
    CYAN = colors.HexColor("#0891B2")
    CYAN_LIGHT = colors.HexColor("#ECFEFF")
    GREEN = colors.HexColor("#16A34A")
    GREEN_LIGHT = colors.HexColor("#DCFCE7")
    RED = colors.HexColor("#DC2626")
    RED_LIGHT = colors.HexColor("#FEE2E2")
    TEXT_DARK = colors.HexColor("#1E293B")
    TEXT_MUTED = colors.HexColor("#64748B")
    BORDER_COLOR = colors.HexColor("#CBD5E1")
    BG_LIGHT = colors.HexColor("#F8FAFC")

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
        "Heading1_Custom",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=13,
        leading=17,
        textColor=PRIMARY,
        spaceBefore=12,
        spaceAfter=6,
    )
    h2_style = ParagraphStyle(
        "Heading2_Custom",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=10.5,
        leading=14,
        textColor=SECONDARY,
        spaceBefore=8,
        spaceAfter=4,
    )
    body_style = ParagraphStyle(
        "Body_Custom",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=8.5,
        leading=12.5,
        textColor=TEXT_DARK,
        spaceAfter=5,
    )
    callout_style = ParagraphStyle(
        "Callout",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=8.5,
        leading=12,
        textColor=colors.HexColor("#92400E"),
    )
    table_cell = ParagraphStyle(
        "TableCell",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=7.5,
        leading=10.5,
        textColor=TEXT_DARK,
    )
    table_cell_bold = ParagraphStyle(
        "TableCellBold",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.5,
        leading=10.5,
        textColor=TEXT_DARK,
    )
    table_cell_header = ParagraphStyle(
        "TableHeader",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=7.5,
        leading=10.5,
        textColor=colors.white,
    )

    story = []

    # ── HEADER BLOCK ─────────────────────────────────────────────────────────
    story.append(Paragraph("STATIC TRACE — 10x UI/UX OVERHAUL SPECIFICATION", title_style))
    story.append(Paragraph(
        "Transforming Mobile Sales App & Web Studio into a Luxury Interior Design Accelerator<br/>"
        "Benchmark: Coohom, Linear, Apple Vision Spatial Tools & High-End European Cabinetry Ateliers",
        subtitle_style
    ))
    story.append(HRFlowable(width="100%", thickness=1.5, color=ACCENT, spaceAfter=10))

    # ── EXECUTIVE SUMMARY ───────────────────────────────────────────────────
    summary_box = [
        [
            Paragraph(
                "<b>Executive Blueprint & Architectural Directive:</b><br/>"
                "Static Trace features robust spatial algorithms and engineering data flow (spatial $(x,y,z)$ coordinates, multi-wall geometry, AutoCAD DXF, and CNC BOM cutlists). However, the interface currently operates as a developer prototype. "
                "This overhaul systematically replaces clunky hybrid webview controls with <b>60fps native Flutter joinery drawers</b>, introduces <b>touch-magnified 36px frosted calibration nodes</b>, elevates Web Studio with a <b>centered floating Linear-style CAD dock</b> with keyboard shortcuts, and packages proposals into a <b>luxury client portal with interactive deposit commitment</b>.",
                callout_style
            )
        ]
    ]
    st_table = Table(summary_box, colWidths=[174 * mm])
    st_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), ACCENT_LIGHT),
        ("BOX", (0, 0), (-1, -1), 1, ACCENT),
        ("PADDING", (0, 0), (-1, -1), 8),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    story.append(st_table)
    story.append(Spacer(1, 10))

    # ── FLAW & 10x ELEVATION MATRIX ──────────────────────────────────────────
    story.append(Paragraph("1. Flaw Matrix & 10x Elevation Strategy", h1_style))
    matrix_data = [
        [
            Paragraph("Surface / Dimension", table_cell_header),
            Paragraph("Current Prototype Flaw", table_cell_header),
            Paragraph("10x Elevated Target State", table_cell_header),
            Paragraph("UX Impact & Benchmark", table_cell_header)
        ],
        [
            Paragraph("<b>Mobile 3D Co-Design</b>", table_cell_bold),
            Paragraph("96px fixed HTML sidebar collides with Flutter budget bar; double reset buttons; cramped touch zones.", table_cell),
            Paragraph("Full-bleed 3D viewport; native Flutter joinery drawer with categorized modules; smooth counting budget odometer.", table_cell),
            Paragraph("Eliminates double-UI collision; 60fps native gestures matching Apple Vision apps.", table_cell)
        ],
        [
            Paragraph("<b>Wall Tracing & Calibration</b>", table_cell_bold),
            Paragraph("2px thin boundary lines; 9px text tags; difficult to grab with fingers on mobile screens.", table_cell),
            Paragraph("36px circular frosted-glass grip nodes; magnifying zoom loupe during drag; 50mm smart grid haptic snapping.", table_cell),
            Paragraph("High precision in-home measurement with zero finger-obscured line error.", table_cell)
        ],
        [
            Paragraph("<b>Consultation Hub & CRM</b>", table_cell_bold),
            Paragraph("Plain card list with basic search; no filter chips; generic offline banner.", table_cell),
            Paragraph("Hero consultation launcher ('Snap, Calibrate, Close'); filter chips (All, Locked, Drafts, Outbox); swipe actions.", table_cell),
            Paragraph("Commercial-grade sales reps dashboard; immediate deal visibility.", table_cell)
        ],
        [
            Paragraph("<b>Web Studio Workbench</b>", table_cell_bold),
            Paragraph("Cramped bottom-left toolbar; tiny nudge buttons; no keyboard shortcuts; no undo/redo.", table_cell),
            Paragraph("Centered Linear-style glass dock; keys 1-4 add, Del removes, Arrows nudge; glowing 3D selection box; Ctrl+Z undo.", table_cell),
            Paragraph("Instant back-office estimator workflow; 3x faster revision cycles.", table_cell)
        ],
        [
            Paragraph("<b>Customer 3D Portal</b>", table_cell_bold),
            Paragraph("Static cards; sudden color jump when toggling styles; direct deposit alert box.", table_cell),
            Paragraph("Luxury homeowner atelier feel; smooth material cross-fades; interactive checkout modal with Apple Pay / Card selector.", table_cell),
            Paragraph("High-trust consumer closing rate; 30-day price guarantee lock.", table_cell)
        ],
        [
            Paragraph("<b>Factory CNC Dispatch</b>", table_cell_bold),
            Paragraph("Basic table styling; text truncation; no material filtering.", table_cell),
            Paragraph("High-contrast precision dark terminal; instant search & material filter chips; sheet yield & nesting gauge.", table_cell),
            Paragraph("Factory-ready handoff for CNC beam saws & nesting routers.", table_cell)
        ]
    ]

    mat_table = Table(matrix_data, colWidths=[36 * mm, 46 * mm, 50 * mm, 42 * mm])
    mat_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), PRIMARY),
        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ("PADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(mat_table)
    story.append(Spacer(1, 14))

    # ── ARCHITECTURAL PILLARS ────────────────────────────────────────────────
    story.append(Paragraph("2. Four Core Architectural Upgrades", h1_style))

    pillars_info = [
        ("Pillar A: Mobile WebView vs. Native Decoupling",
         "The single greatest UX defect on mobile was embedding HTML sidebar controls (#sidebar) and HUD overlays inside the WebView, which fought with native Flutter widgets. In the overhaul, WebView is strictly designated as a pure WebGL canvas rendering surface. All interaction (drawer trays, style selector, budget odometer, action sheet) is native Flutter with full platform typography, smooth 60fps animations, and tactile haptic feedback."),
        ("Pillar B: Three.js Visual Realism & Camera Lerping",
         "Upgrades the 3D rendering pipeline across mobile and web with THREE.PCFSoftShadowMap, subtle ground ambient occlusion under cabinet plinths, beveled quartz edges, and physical brushed metallic handles. Camera perspective switches (Orbit, Top, Front) now execute silky orbital lerp transitions over 450ms rather than instantaneous jump cuts."),
        ("Pillar C: Linear-Style Glass CAD Dock (Web Studio)",
         "Redesigns the back-office studio interface around a centered floating glass dock (backdrop-blur-xl, border-white/10). Adds full keyboard hotkeys (1-4 for module insertion, Delete/Backspace for removal, Arrow keys for 100mm nudging, Ctrl+Z for undo). Placed cabinets highlight with an animated amber wireframe bounding box and instant dimension inspector."),
        ("Pillar D: High-Trust Customer Proposal Portal & Payment Drawer",
         "The shareable client link (/view/{quote_id}) transforms into a luxury DTC showroom. Homeowners experience morning/evening ambient lighting toggles, material cross-fades, and an interactive payment drawer with 30-day pricing guarantee, terms of production reservation, and multi-method deposit commitment ($250).")
    ]

    for title, desc in pillars_info:
        story.append(Paragraph(title, h2_style))
        story.append(Paragraph(desc, body_style))

    story.append(PageBreak())

    # ── SYSTEM ARCHITECTURE & CODE SPECIFICATION ─────────────────────────────
    story.append(Paragraph("3. Component Engineering Specifications", h1_style))

    story.append(Paragraph("Mobile Flutter App Architecture (`lib/`)", h2_style))
    flutter_items = [
        [
            Paragraph("File Target", table_cell_header),
            Paragraph("Refactor Scope & Design Modifications", table_cell_header),
        ],
        [
            Paragraph("<b>lib/shared/theme.dart</b>", table_cell_bold),
            Paragraph("Implement unified Obsidian luxury palette (bg: #090C10, surface: #121620, border: 1px subtle hairline, radius: pill 999, card 18). Configure GoogleFonts.plusJakartaSans and JetBrains Mono for telemetry.", table_cell),
        ],
        [
            Paragraph("<b>lib/features/trace/screens/trace_screen.dart</b>", table_cell_bold),
            Paragraph("Replace 2px boundary lines with 36px circular frosted grip nodes with drag magnification loupe; smart 50mm grid snapping with haptic feedback ticks; updated bottom joinery toolbar.", table_cell),
        ],
        [
            Paragraph("<b>lib/features/viewer/screens/viewer_screen.dart</b>", table_cell_bold),
            Paragraph("Inject CSS/JS into WebView to hide #sidebar and #hud. Add native sliding Joinery Tray (Base, Wall, Tall modules). Add TweenAnimationBuilder live odometer counter for dynamic pricing. Floating style pills with glowing active indicators.", table_cell),
        ],
        [
            Paragraph("<b>lib/features/intake/screens/intake_hub_screen.dart</b>", table_cell_bold),
            Paragraph("Add Hero Consultation Launcher card (Camera Scan, 2D Floorplan Calibrate, Template Room). Add filter pills (All, Priority Locked, Estimates, Offline Queue). Add swipe-to-share and auto-sync status pulse.", table_cell),
        ],
        [
            Paragraph("<b>lib/features/viewer/widgets/closing_modal.dart</b>", table_cell_bold),
            Paragraph("Luxury order agreement card with 3D thumbnail, bezier-smoothed signature canvas with undo/clear, and celebration confetti / WhatsApp link generator upon deal commitment.", table_cell),
        ],
        [
            Paragraph("<b>assets/3d/index.html</b>", table_cell_bold),
            Paragraph("Add .is-native-app flag to suppress DOM overlays. Enhance Three.js materials with soft contact shadows, beveled countertops, and smooth camera orbital interpolation.", table_cell),
        ]
    ]
    fl_table = Table(flutter_items, colWidths=[55 * mm, 119 * mm])
    fl_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), SECONDARY),
        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ("PADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(fl_table)
    story.append(Spacer(1, 10))

    story.append(Paragraph("Web Studio, Portal & Factory Suites (`backend/static/`)", h2_style))
    web_items = [
        [
            Paragraph("Web Endpoint / File", table_cell_header),
            Paragraph("Design Enhancement & Interaction Implementation", table_cell_header),
        ],
        [
            Paragraph("<b>backend/static/studio/index.html</b><br/>(Studio Workbench)", table_cell_bold),
            Paragraph("Centered floating CAD dock with glassmorphism; keyboard hotkeys (1-4, Del, Arrows, Ctrl+Z); glowing amber 3D selection bounding box; smooth camera view lerping; real-time recalculation and persistent PUT API sync.", table_cell),
        ],
        [
            Paragraph("<b>backend/static/portal/index.html</b><br/>(Customer Proposal Portal)", table_cell_bold),
            Paragraph("Homeowner showroom aesthetic; day/evening lighting toggles; material cross-fade on style switch; full-featured slot deposit checkout drawer with card / Apple Pay selector and 30-day pricing guarantee terms.", table_cell),
        ],
        [
            Paragraph("<b>backend/static/studio/factory.html</b><br/>(CNC Factory Dispatch)", table_cell_bold),
            Paragraph("High-contrast precision dark terminal; live search & material filter chips; sheet yield & nesting efficiency gauge; 33-part itemized cutlist table with copyable CNC panel codes.", table_cell),
        ]
    ]
    web_table = Table(web_items, colWidths=[55 * mm, 119 * mm])
    web_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), SECONDARY),
        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ("PADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(web_table)
    story.append(Spacer(1, 14))

    # ── VERIFICATION & ROADMAP ────────────────────────────────────────────────
    story.append(Paragraph("4. Verification & Quality Assurance Protocol", h1_style))
    qa_points = [
        "<b>1. Automated Mobile Unit Tests:</b> Execute `flutter test` across all 21 test suites ensuring zero regression across CPQ calculations, boundary math, offline store, and widget smoke tests.",
        "<b>2. Backend Integration Suite:</b> Execute `python backend/test_studio.py` verifying projects API, master catalog, multi-wall DXF generation, 33-part cutlist CSV, and customer deposit payments.",
        "<b>3. Playwright Visual Verification & Screenshot Evidence:</b> Run Edge headless capture scripts to record high-resolution screenshots of the upgraded Studio Workbench, Customer Portal, and Factory Dispatch into `plan/screenshots/` and mirror into the persistent brain directory.",
        "<b>4. Double-UI Collision Audit:</b> Verify that inside the mobile 3D Viewer WebView, all DOM buttons are suppressed and native Flutter bottom joinery tray functions smoothly."
    ]
    for pt in qa_points:
        story.append(Paragraph(f"• {pt}", body_style))
        story.append(Spacer(1, 2))

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"[SUCCESS] PDF generated at {filename}")


if __name__ == "__main__":
    out_dir = Path("plan")
    out_dir.mkdir(exist_ok=True)
    pdf_file = str(out_dir / "UI_UX_10x_Overhaul_Plan.pdf")
    build_pdf(pdf_file)

    brain_dir = Path(r"C:\Users\User\.gemini\antigravity\brain\3479f5a9-6103-4821-b60a-cb5ccf5febc6")
    if brain_dir.exists():
        brain_pdf = brain_dir / "UI_UX_10x_Overhaul_Plan.pdf"
        shutil.copyfile(pdf_file, str(brain_pdf))
        print(f"[COPIED] Brain copy generated at {brain_pdf}")
