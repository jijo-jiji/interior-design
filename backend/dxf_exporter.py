"""
CAD DXF Exporter for Kitchen & Wardrobe Layouts
Generates standard AutoCAD Release 12 ASCII DXF files for factory cutting,
CNC nesting machines, and architectural CAD coordination.
Supports multi-wall (L-Shape, Galley) layouts, leader dimensions, and cabinet part IDs.
"""

from __future__ import annotations
from typing import Any


def generate_dxf(project: dict[str, Any]) -> str:
    """
    Exports a project's wall, return walls, obstacles, and cabinet layouts to standard ASCII DXF format.
    Units are in millimeters (mm).
    """
    wall = project.get("wall", {})
    wall_w = float(wall.get("width_mm", 4000.0))
    wall_h = float(wall.get("height_mm", 2700.0))
    wall_d = float(wall.get("depth_mm", 150.0))
    shape = wall.get("shape", "singleWall")
    return_mm = float(wall.get("return_mm", 0.0))

    obstacles = project.get("obstacles", [])
    cabinets = project.get("placed_cabinets", [])

    dxf_lines: list[str] = []

    def code(group: int, val: Any) -> None:
        dxf_lines.append(f"{group}\n{val}")

    # ── HEADER SECTION ───────────────────────────────────────────────────────
    code(0, "SECTION")
    code(2, "HEADER")
    code(9, "$ACADVER")
    code(1, "AC1009")  # AutoCAD Release 12
    code(9, "$INSUNITS")
    code(70, 4)        # 4 = Millimeters
    code(0, "ENDSEC")

    # ── TABLES SECTION (LAYERS) ──────────────────────────────────────────────
    code(0, "SECTION")
    code(2, "TABLES")
    code(0, "TABLE")
    code(2, "LAYER")
    code(70, 8)

    layers = [
        ("0", 7),              # Default white
        ("WALL_MAIN", 7),      # White/Black
        ("WALL_RETURN", 5),    # Blue
        ("OBSTACLES", 1),      # Red
        ("CABINETS_BASE", 3),  # Green
        ("CABINETS_WALL", 4),  # Cyan
        ("CABINETS_TALL", 6),  # Magenta
        ("DIMENSIONS", 2),     # Yellow
        ("PART_NUMBERS", 30),  # Orange/Dark
    ]

    for name, color in layers:
        code(0, "LAYER")
        code(2, name)
        code(70, 0)
        code(62, color)
        code(6, "CONTINUOUS")

    code(0, "ENDTAB")
    code(0, "ENDSEC")

    # ── BLOCKS SECTION (Empty) ───────────────────────────────────────────────
    code(0, "SECTION")
    code(2, "BLOCKS")
    code(0, "ENDSEC")

    # ── ENTITIES SECTION ─────────────────────────────────────────────────────
    code(0, "SECTION")
    code(2, "ENTITIES")

    def draw_line(x1: float, y1: float, x2: float, y2: float, layer: str = "0") -> None:
        code(0, "LINE")
        code(8, layer)
        code(10, f"{x1:.2f}")
        code(20, f"{y1:.2f}")
        code(30, "0.0")
        code(11, f"{x2:.2f}")
        code(21, f"{y2:.2f}")
        code(31, "0.0")

    def draw_rect(x: float, y: float, w: float, h: float, layer: str = "0") -> None:
        draw_line(x, y, x + w, y, layer)
        draw_line(x + w, y, x + w, y + h, layer)
        draw_line(x + w, y + h, x, y + h, layer)
        draw_line(x, y + h, x, y, layer)

    def draw_text(x: float, y: float, height: float, text: str, layer: str = "DIMENSIONS") -> None:
        code(0, "TEXT")
        code(8, layer)
        code(10, f"{x:.2f}")
        code(20, f"{y:.2f}")
        code(30, "0.0")
        code(40, f"{height:.2f}")
        code(1, text)

    def draw_dim_h(x1: float, x2: float, y: float, label: str, layer: str = "DIMENSIONS") -> None:
        """Draws a horizontal dimension leader with end ticks and centered annotation."""
        tick = 25.0
        draw_line(x1, y, x2, y, layer=layer)
        draw_line(x1, y - tick, x1, y + tick, layer=layer)
        draw_line(x2, y - tick, x2, y + tick, layer=layer)
        mid_x = (x1 + x2) / 2.0 - (len(label) * 11.0)
        draw_text(mid_x, y + 12.0, 32.0, label, layer=layer)

    def draw_dim_v(x: float, y1: float, y2: float, label: str, layer: str = "DIMENSIONS") -> None:
        """Draws a vertical dimension leader with end ticks and annotation."""
        tick = 25.0
        draw_line(x, y1, x, y2, layer=layer)
        draw_line(x - tick, y1, x + tick, y1, layer=layer)
        draw_line(x - tick, y2, x + tick, y2, layer=layer)
        mid_y = (y1 + y2) / 2.0 - 15.0
        draw_text(x + 12.0, mid_y, 32.0, label, layer=layer)

    # ── 1. FRONT ELEVATION VIEW ───────────────────────────────────────────────
    # Main Wall Elevation at origin (0, 0)
    draw_rect(0, 0, wall_w, wall_h, layer="WALL_MAIN")
    draw_text(0, wall_h + 120, 65, f"FRONT ELEVATION — MAIN WALL ({wall_w:.0f}mm W x {wall_h:.0f}mm H)", layer="DIMENSIONS")
    # Wall Dimensions Leader
    draw_dim_h(0, wall_w, wall_h + 40, f"WIDTH: {wall_w:.0f} mm")
    draw_dim_v(-80, 0, wall_h, f"HEIGHT: {wall_h:.0f} mm")

    # Obstacles
    for obs in obstacles:
        ox = float(obs.get("distance_from_left_mm", 0))
        oy = float(obs.get("distance_from_floor_mm", 0))
        ow = float(obs.get("width_mm", 900))
        oh = float(obs.get("height_mm", 2100))
        otype = obs.get("type", "window").upper()
        draw_rect(ox, oy, ow, oh, layer="OBSTACLES")
        draw_text(ox + 20, oy + oh / 2, 35, f"{otype} {ow:.0f}x{oh:.0f}", layer="OBSTACLES")

    # Return Wall Elevation (if L-Shape)
    if shape == "lShape" and return_mm > 0:
        return_elev_x = wall_w + 600.0
        draw_rect(return_elev_x, 0, return_mm, wall_h, layer="WALL_RETURN")
        draw_text(return_elev_x, wall_h + 120, 65, f"SIDE ELEVATION — RETURN WALL ({return_mm:.0f}mm W x {wall_h:.0f}mm H)", layer="DIMENSIONS")
        draw_dim_h(return_elev_x, return_elev_x + return_mm, wall_h + 40, f"RETURN: {return_mm:.0f} mm")

    # ── 2. PLAN VIEW (TOP-DOWN FLOORPLAN) ────────────────────────────────────
    # Positioned below the elevation view with 1200mm clearance
    plan_y = -(wall_d + 1200.0)
    # Main Wall in Plan
    draw_rect(0, plan_y, wall_w, wall_d, layer="WALL_MAIN")
    draw_text(0, plan_y - 200, 65, "TOP-DOWN PLAN VIEW (FLOORPLAN CNC LAYOUT)", layer="DIMENSIONS")

    # Return Wall in Plan (Corner at left edge)
    if shape == "lShape" and return_mm > 0:
        # Return wall extends forward/south from left edge of main wall
        draw_rect(-wall_d, plan_y - return_mm + wall_d, wall_d, return_mm, layer="WALL_RETURN")
        draw_dim_v(-wall_d - 80, plan_y - return_mm + wall_d, plan_y + wall_d, f"RETURN {return_mm:.0f} mm")

    # ── 3. CABINETS & CNC PART LABELS ─────────────────────────────────────────
    for idx, cab in enumerate(cabinets, start=1):
        part_tag = f"CAB-{idx:02d}"
        ctype = cab.get("cabinet_type", "base_600")
        cw = float(cab.get("width_mm", 600.0))
        ch = float(cab.get("height_mm", 850.0))
        cd = float(cab.get("depth_mm", 600.0))
        clabel = cab.get("label", ctype)

        # X position relative to wall left (converted from Three.js center-offset)
        x_scene = float(cab.get("x_mm", 0.0))
        cx = (wall_w / 2.0) + x_scene - (cw / 2.0)

        is_wall = "wall" in ctype
        is_tall = "tall" in ctype
        layer_name = "CABINETS_WALL" if is_wall else ("CABINETS_TALL" if is_tall else "CABINETS_BASE")

        # Elevation Y
        cy = 1400.0 if is_wall else 0.0

        # Draw in Elevation view
        draw_rect(cx, cy, cw, ch, layer=layer_name)

        # Part Number Tag Box in Elevation
        draw_rect(cx + 15, cy + ch - 80, 160, 50, layer="PART_NUMBERS")
        draw_text(cx + 25, cy + ch - 65, 30, f"[{part_tag}]", layer="PART_NUMBERS")

        # Cabinet Description & Size Text
        draw_text(cx + 15, cy + ch / 2, 28, f"{clabel}", layer=layer_name)
        draw_text(cx + 15, cy + ch / 2 - 40, 24, f"{cw:.0f}x{ch:.0f}x{cd:.0f}mm", layer="DIMENSIONS")

        # Baseline Cabinet Width Dimension
        draw_dim_h(cx, cx + cw, cy - 50, f"{cw:.0f}", layer="DIMENSIONS")

        # Draw in Plan view (projected forward from wall face)
        draw_rect(cx, plan_y + wall_d, cw, cd, layer=layer_name)
        draw_text(cx + 15, plan_y + wall_d + cd / 2 - 15, 28, f"[{part_tag}] {clabel}", layer=layer_name)

    # ── END OF ENTITIES & FILE ────────────────────────────────────────────────
    code(0, "ENDSEC")
    code(0, "EOF")

    return "\n".join(dxf_lines)
