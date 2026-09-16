import os
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm, inch
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

        # Running header (on pages after page 1)
        if self._pageNumber > 1:
            self.drawString(
                20 * mm,
                297 * mm - 14 * mm,
                "Interior Design Sales Accelerator — Coohom Benchmark & Architecture"
            )
            self.setStrokeColor(colors.HexColor("#CBD5E0"))
            self.setLineWidth(0.5)
            self.line(20 * mm, 297 * mm - 16 * mm, 210 * mm - 20 * mm, 297 * mm - 16 * mm)

        # Running footer
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(210 * mm - 20 * mm, 12 * mm, page_str)
        self.drawString(
            20 * mm,
            12 * mm,
            "Confidential & Proprietary — Prepared for Product Architecture Review"
        )
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.5)
        self.line(20 * mm, 16 * mm, 210 * mm - 20 * mm, 16 * mm)

        self.restoreState()


def build_pdf(filename):
    doc = SimpleDocTemplate(
        filename,
        pagesize=A4,
        leftMargin=20 * mm,
        rightMargin=20 * mm,
        topMargin=22 * mm,
        bottomMargin=22 * mm,
    )

    styles = getSampleStyleSheet()

    # Brand Colors
    PRIMARY = colors.HexColor("#0F172A")    # Deep Slate
    SECONDARY = colors.HexColor("#1E293B")  # Slate 800
    ACCENT = colors.HexColor("#D97706")     # Warm Amber
    ACCENT_LIGHT = colors.HexColor("#FEF3C7")
    TEXT_DARK = colors.HexColor("#1E293B")
    TEXT_MUTED = colors.HexColor("#64748B")
    BORDER_COLOR = colors.HexColor("#E2E8F0")
    BG_LIGHT = colors.HexColor("#F8FAFC")

    # Typography styles
    title_style = ParagraphStyle(
        "CoverTitle",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=21,
        leading=26,
        textColor=PRIMARY,
        spaceAfter=6,
    )

    subtitle_style = ParagraphStyle(
        "CoverSubtitle",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=11,
        leading=16,
        textColor=TEXT_MUTED,
        spaceAfter=14,
    )

    h1_style = ParagraphStyle(
        "Heading1_Custom",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=13,
        leading=17,
        textColor=PRIMARY,
        spaceBefore=14,
        spaceAfter=6,
        keepWithNext=True,
    )

    h2_style = ParagraphStyle(
        "Heading2_Custom",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=10.5,
        leading=14,
        textColor=SECONDARY,
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True,
    )

    body_style = ParagraphStyle(
        "Body_Custom",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=9,
        leading=13.5,
        textColor=TEXT_DARK,
        spaceAfter=6,
    )

    bullet_style = ParagraphStyle(
        "Bullet_Custom",
        parent=body_style,
        leftIndent=12,
        firstLineIndent=-10,
        spaceAfter=3,
    )

    callout_style = ParagraphStyle(
        "Callout_Text",
        parent=styles["Normal"],
        fontName="Helvetica-Oblique",
        fontSize=8.5,
        leading=12.5,
        textColor=colors.HexColor("#78350F"),
    )

    table_header_style = ParagraphStyle(
        "TableHeader",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=8.5,
        leading=11,
        textColor=colors.white,
    )

    table_cell_style = ParagraphStyle(
        "TableCell",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=8,
        leading=11,
        textColor=TEXT_DARK,
    )

    table_cell_bold = ParagraphStyle(
        "TableCellBold",
        parent=table_cell_style,
        fontName="Helvetica-Bold",
    )

    story = []

    # ── HEADER BANNER ──────────────────────────────────────────────────────────
    story.append(Paragraph("High-Speed In-Person Interior Design Sales Accelerator", title_style))
    story.append(Paragraph(
        "Strategic Analysis of Coohom, Sales Closing Psychology, Multi-Modal Room Ingestion & Dual Mobile/Web Architecture",
        subtitle_style
    ))
    story.append(HRFlowable(width="100%", thickness=1.5, color=ACCENT, spaceBefore=0, spaceAfter=12))

    # Metadata badges table
    meta_data = [
        [
            Paragraph("<b>Target Domain:</b> Interior Design & Cabinetry Sales", table_cell_style),
            Paragraph("<b>Benchmark:</b> Coohom.com Cloud Suite", table_cell_style),
            Paragraph("<b>Core KPI:</b> 15-Minute Consultation-to-Close", table_cell_style),
        ]
    ]
    meta_table = Table(meta_data, colWidths=[60 * mm, 55 * mm, 55 * mm])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), BG_LIGHT),
        ('BOX', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 10))

    # ── EXECUTIVE SUMMARY ───────────────────────────────────────────────────────
    story.append(Paragraph("Executive Summary: The Consultation-to-Quotation Bottleneck", h1_style))
    story.append(Paragraph(
        "In the interior design and custom cabinetry industry, traditional sales funnels experience a devastating "
        "<b>40% to 65% drop-off rate</b> between the initial client consultation and final contract signing. "
        "This friction is caused by the multi-day <i>'Design & Estimation Void'</i>: a sales rep visits a client's site, "
        "takes manual measurements, and retreats to the office for 3 to 7 days to manually build 3D models and calculate the Bill of Quantities (BOQ). "
        "By the time the follow-up meeting occurs, client urgency has dropped, competing firms have submitted quotes, and budget anxieties mount.",
        body_style
    ))
    story.append(Paragraph(
        "<b>The Solution:</b> A <i>Single-Session In-Person Closing Machine</i>. Equipping sales reps with an interactive tablet and web-synced tool that "
        "captures the room, customizes parametric layouts magnetically, calculates a live dynamic budget, and collects a digital signature and deposit in under 15 minutes.",
        body_style
    ))
    story.append(Spacer(1, 8))

    # ── SECTION 1: COOHOM BENCHMARK ────────────────────────────────────────────
    story.append(Paragraph("1. Coohom Benchmark: Why Desktop Tools Fail in Live Sales", h1_style))
    story.append(Paragraph(
        "Coohom is widely celebrated for its robust desktop capabilities (1M+ assets, ExaCloud ray-tracing, parametric cabinetry, and CAD/BIM drawing outputs). "
        "However, field testing and practitioner feedback reveal that attempting to use Coohom in front of a live client introduces severe operational failure points:",
        body_style
    ))

    # Comparison Table: Coohom vs. Sales Accelerator
    coohom_data = [
        [
            Paragraph("<b>Dimension</b>", table_header_style),
            Paragraph("<b>Coohom Desktop Workflow</b>", table_header_style),
            Paragraph("<b>Sales Accelerator Required UX</b>", table_header_style),
        ],
        [
            Paragraph("<b>Primary Hardware</b>", table_cell_bold),
            Paragraph("Desktop workstation, dual monitors, mouse & keyboard.", table_cell_style),
            Paragraph("Touchscreen tablet (Android/iPad) or ultralight laptop on the client's couch.", table_cell_style),
        ],
        [
            Paragraph("<b>Catalog Scope</b>", table_cell_bold),
            Paragraph("1,000,000+ items. Overwhelming search menus cause choice paralysis.", table_cell_style),
            Paragraph("3 to 5 Curated Style Archetypes (Japandi, Minimalist, Nordic, Industrial).", table_cell_style),
        ],
        [
            Paragraph("<b>Object Manipulation</b>", table_cell_bold),
            Paragraph("Precision 3D X/Y/Z transformation gizmo. Prone to missed clicks on touch.", table_cell_style),
            Paragraph("Magnetic smart-snapping: units snap flush to adjacent cabinets and wall faces.", table_cell_style),
        ],
        [
            Paragraph("<b>Pricing Feedback</b>", table_cell_bold),
            Paragraph("Disconnected. Requires manual export to separate quotation spreadsheets.", table_cell_style),
            Paragraph("Live Budget Odometer: Instant real-time CPQ calculation as items or finishes change.", table_cell_style),
        ],
        [
            Paragraph("<b>Rendering Latency</b>", table_cell_bold),
            Paragraph("Cloud ray-tracing (1 to 5 min wait). Dependent on stable high-speed Wi-Fi.", table_cell_style),
            Paragraph("Instant 60 FPS local WebGL / Three.js. 100% offline-safe in residential basements.", table_cell_style),
        ],
        [
            Paragraph("<b>Deal Closing Bridge</b>", table_cell_bold),
            Paragraph("Ends with 3D image or panorama link. No on-site commitment step.", table_cell_style),
            Paragraph("On-screen finger signature pad, binding proposal PDF, and Stripe/QR deposit link.", table_cell_style),
        ]
    ]

    coohom_table = Table(coohom_data, colWidths=[34 * mm, 68 * mm, 68 * mm])
    coohom_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), PRIMARY),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ]))
    story.append(coohom_table)
    story.append(Spacer(1, 10))

    # ── SECTION 2: UX BLIND SPOTS FOR SOFTWARE ENGINEERS ───────────────────────
    story.append(Paragraph("2. Interior Design UX Deep Dive: Bridging Engineer Blind Spots", h1_style))
    story.append(Paragraph(
        "Software engineers intuitively approach interior design as a 3D geometric modeling problem. "
        "However, client consultations are high-stakes sales conversations governed by spatial psychology, loss aversion, and ergonomics:",
        body_style
    ))

    blindspots = [
        ("Blind Spot 1: The 'Blank Canvas' Trap",
         "Giving a client an empty 3D room and asking them to choose cabinets induces paralysis. "
         "<b>Solution:</b> Curated Style Archetypes. Tapping 'Japandi Warmth' instantly skins the room with matched wall tones, carcass wood, countertop quartz, and hardware."),
        ("Blind Spot 2: Free 3D Gizmos vs. Magnetic Constraint Snapping",
         "Touch dragging with 3D gizmos causes cabinets to clip through walls, rotate awkwardly, or float. "
         "<b>Solution:</b> Magnetic rails. Cabinets are locked to the wall plane and automatically snap flush to neighbors when dragged within 120mm."),
        ("Blind Spot 3: Spatial Clearances & Ergonomic Safety Rules",
         "A layout that ignores building codes or workflow ergonomics (e.g. blocking a window, or violating the 900mm kitchen walkway clearance) ruins trust. "
         "<b>Solution:</b> Visual 'soft collision' guides that highlight clearance thresholds around door swings and worktops."),
        ("Blind Spot 4: Price Transparency & The 'Budget Odometer'",
         "Hiding the price until the end creates anxiety and sticker shock. "
         "<b>Solution:</b> A persistent bottom ticker showing Total ($12,450), Monthly ($289/mo), and Deposit ($300). When a finish is upgraded, the odometer animates smoothly."),
        ("Blind Spot 5: The Closing Bridge (Contract & Deposit)",
         "A great 3D demo without a commitment mechanism results in the client saying 'Thanks, email me the file'—and then ghosting. "
         "<b>Solution:</b> On-screen finger signing, production slot reservation, and automated WhatsApp proposal dispatch.")
    ]

    for title, desc in blindspots:
        story.append(Paragraph(f"• <b>{title}:</b> {desc}", bullet_style))
    story.append(Spacer(1, 10))

    # ── SECTION 3: MULTI-MODAL ROOM INPUT PIPELINE ────────────────────────────
    story.append(Paragraph("3. Multi-Modal Room Input Pipeline", h1_style))
    story.append(Paragraph(
        "To guarantee zero failure on-site, the sales rep must never be blocked if a floor plan is missing or camera scanning is inconvenient. "
        "The system incorporates three robust input tiers:",
        body_style
    ))

    input_tiers = [
        [
            Paragraph("<b>Modality</b>", table_header_style),
            Paragraph("<b>Technical Implementation</b>", table_header_style),
            Paragraph("<b>Best Used When</b>", table_header_style),
            Paragraph("<b>Speed to 3D</b>", table_header_style),
        ],
        [
            Paragraph("<b>Tier 1: Camera Wall Trace</b>", table_cell_bold),
            Paragraph("Snap photo of real wall (eliminates AR drift). Drag obstacle boxes (doors/windows) over frozen frame with real-world mm scaling.", table_cell_style),
            Paragraph("On-site residential visits, single-wall kitchen or wardrobe renovations.", table_cell_style),
            Paragraph("<b>60 - 90 seconds</b>", table_cell_style),
        ],
        [
            Paragraph("<b>Tier 2: 2D Floor Plan Processing</b>", table_cell_bold),
            Paragraph("Ingest architect PDF, real estate brochure, or paper blueprint photo. 2-point scale calibration, vector wall extraction & 3D extrusion.", table_cell_style),
            Paragraph("Client already possesses official developer floor plans or architectural drawings.", table_cell_style),
            Paragraph("<b>30 - 45 seconds</b>", table_cell_style),
        ],
        [
            Paragraph("<b>Tier 3: 10s Template Preset</b>", table_cell_bold),
            Paragraph("Select Single Wall, L-Shape, Galley, or U-Shape room preset. Two sliders: Width (mm) and Ceiling Height (mm).", table_cell_style),
            Paragraph("Client meets in a showroom or coffee shop without blueprints or photos.", table_cell_style),
            Paragraph("<b>10 seconds</b>", table_cell_style),
        ]
    ]

    input_table = Table(input_tiers, colWidths=[38 * mm, 62 * mm, 45 * mm, 25 * mm])
    input_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), SECONDARY),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(input_table)
    story.append(Spacer(1, 10))

    # ── SECTION 4: DUAL-PLATFORM ARCHITECTURE ──────────────────────────────────
    story.append(Paragraph("4. Dual-Platform Architecture: Mobile/Tablet vs. Web Studio", h1_style))
    story.append(Paragraph(
        "Instead of forcing a single interface to serve both contradictory user personas, the architecture cleanly bisects into two specialized frontends backed by a unified cloud core:",
        body_style
    ))

    dual_data = [
        [
            Paragraph("<b>Layer</b>", table_header_style),
            Paragraph("<b>Mobile / Tablet Sales App (The Closer)</b>", table_header_style),
            Paragraph("<b>Web Workbench (The Studio Hub)</b>", table_header_style),
        ],
        [
            Paragraph("<b>Target User</b>", table_cell_bold),
            Paragraph("Field Sales Representative, Design Consultant.", table_cell_style),
            Paragraph("Senior Interior Designer, Estimator, CNC Factory Admin.", table_cell_style),
        ],
        [
            Paragraph("<b>Primary Goal</b>", table_cell_bold),
            Paragraph("Fast in-person co-design, live visual quoting, and digital deposit signing.", table_cell_style),
            Paragraph("Master catalog configuration, complex joinery detailing, and CNC DXF export.", table_cell_style),
        ],
        [
            Paragraph("<b>Tech Stack</b>", table_cell_bold),
            Paragraph("<b>Flutter + Three.js WebView</b> (High performance, camera access, offline support).", table_cell_style),
            Paragraph("<b>React / Next.js + Three.js</b> (Desktop mouse precision, multi-window layout).", table_cell_style),
        ],
        [
            Paragraph("<b>Key Features</b>", table_cell_bold),
            Paragraph("• Camera wall tracing & 2D plan import<br/>• 1-tap style archetype switching<br/>• Magnetic cabinet snapping<br/>• Dynamic Budget Odometer<br/>• On-screen finger signing & deposit collection", table_cell_style),
            Paragraph("• Supplier catalog & material price matrices<br/>• Custom millimeter parametric joinery<br/>• Multi-room whole-house project coordination<br/>• 4K cloud photorealistic ray-tracing queue<br/>• Automated cutting list & factory CNC export", table_cell_style),
        ],
        [
            Paragraph("<b>Data Sync</b>", table_cell_bold),
            Paragraph("<font color='#D97706'><b>Lean Scene JSON:</b></font> Instant sync via WebSockets / Supabase; full round-trip between tablet and web.", table_cell_style),
            Paragraph("<font color='#D97706'><b>Unified Backend:</b></font> FastAPI pricing engine, PostgreSQL relational DB, and ReportLab PDF generator.", table_cell_style),
        ]
    ]

    dual_table = Table(dual_data, colWidths=[30 * mm, 70 * mm, 70 * mm])
    dual_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), PRIMARY),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ]))
    story.append(dual_table)
    story.append(Spacer(1, 10))

    # ── SECTION 5: 15-MINUTE SALES WORKFLOW TIMELINE ───────────────────────────
    story.append(Paragraph("5. End-to-End In-Person Sales Workflow (The 15-Minute Close)", h1_style))
    story.append(Paragraph(
        "A structured consultative framework designed to guide the customer smoothly from initial measurement to deposit commitment:",
        body_style
    ))

    timeline_data = [
        [
            Paragraph("<b>Phase</b>", table_header_style),
            Paragraph("<b>Duration</b>", table_header_style),
            Paragraph("<b>Sales Action & Customer Experience</b>", table_header_style),
            Paragraph("<b>System State</b>", table_header_style),
        ],
        [
            Paragraph("<b>1. Space Capture</b>", table_cell_bold),
            Paragraph("Min 0 - 3", table_cell_style),
            Paragraph("Snap photo of wall or import client's floorplan PDF. Rep drags door/window boxes. Client sees room digitized in real time.", table_cell_style),
            Paragraph("Parametric 3D wall mesh extruded in local Three.js.", table_cell_style),
        ],
        [
            Paragraph("<b>2. Style Co-Creation</b>", table_cell_bold),
            Paragraph("Min 3 - 5", table_cell_style),
            Paragraph("Present 4 Curated Archetypes (e.g. Japandi Natural). One tap skins the room. Eliminates catalog overwhelm; establishes aesthetic alignment.", table_cell_style),
            Paragraph("PBR materials applied instantly to scene.", table_cell_style),
        ],
        [
            Paragraph("<b>3. Modular Layout</b>", table_cell_bold),
            Paragraph("Min 5 - 10", table_cell_style),
            Paragraph("Rep taps 4 to 6 base and wall cabinets. Units snap magnetically along the wall. Client participates by dragging modules.", table_cell_style),
            Paragraph("Collision boundaries enforced; snap guides pulse.", table_cell_style),
        ],
        [
            Paragraph("<b>4. Dynamic Quoting</b>", table_cell_bold),
            Paragraph("Min 10 - 12", table_cell_style),
            Paragraph("Live Budget Odometer shows itemized total ($12,850) and monthly financing ($310/mo). Rep compares 'Good / Better / Best' material upgrades.", table_cell_style),
            Paragraph("Real-time CPQ engine recalculates line items.", table_cell_style),
        ],
        [
            Paragraph("<b>5. The Commitment</b>", table_cell_bold),
            Paragraph("Min 12 - 15", table_cell_style),
            Paragraph("Rep taps 'Lock In Design'. 1-page proposal generated. Client signs with finger on tablet to reserve production slot ($250 deposit).", table_cell_style),
            Paragraph("PDF stamped with signature, emailed & texted to client.", table_cell_style),
        ]
    ]

    timeline_table = Table(timeline_data, colWidths=[32 * mm, 20 * mm, 78 * mm, 40 * mm])
    timeline_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), SECONDARY),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG_LIGHT]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(timeline_table)
    story.append(Spacer(1, 12))

    # ── CALLOUT BOX ────────────────────────────────────────────────────────────
    callout_data = [[
        Paragraph(
            "<b>Strategic Takeaway:</b> Traditional platforms like Coohom optimize for the drafting table and rendering farm. "
            "Our competitive advantage is optimizing for the <i>consultation couch</i>. By automating snap-alignment, constraining options to "
            "curated archetypes, and linking design choices directly to transparent monthly pricing, we eliminate the 7-day quotation void "
            "and empower sales representatives to close deals on the spot.",
            callout_style
        )
    ]]
    callout_box = Table(callout_data, colWidths=[170 * mm])
    callout_box.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), ACCENT_LIGHT),
        ('BOX', (0, 0), (-1, -1), 1, ACCENT),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('LEFTPADDING', (0, 0), (-1, -1), 10),
        ('RIGHTPADDING', (0, 0), (-1, -1), 10),
    ]))
    story.append(callout_box)

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"[OK] Successfully built PDF: {filename}")


if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(__file__), "..", "plan")
    os.makedirs(out_dir, exist_ok=True)
    pdf_path = os.path.abspath(os.path.join(out_dir, "High_Speed_Interior_Design_Sales_Accelerator.pdf"))
    build_pdf(pdf_path)
