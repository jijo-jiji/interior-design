"""
Precision CNC Cutting Schedule (Cutlist) Generator for Millwork & Cabinet Factories.
Generates an exportable CSV schedule detailing each panel, thickness, grain direction,
and edgebanding specs for beam saws and nesting CNC routers.
"""

from __future__ import annotations
import io
import csv
from typing import Any

def generate_cutlist_csv(project: dict[str, Any]) -> str:
    output = io.StringIO()
    writer = csv.writer(output)

    # Standard CNC Millwork CSV Header
    writer.writerow([
        "Part_ID",
        "Cabinet_Ref",
        "Cabinet_Type",
        "Part_Name",
        "Material_Core",
        "Finish_Face",
        "Length_mm",
        "Width_mm",
        "Thickness_mm",
        "Qty",
        "Edgebanding_Spec",
        "Grain_Direction"
    ])

    cabinets = project.get("placed_cabinets", [])
    style = project.get("style_archetype", "japandi")

    finish_map = {
        "japandi": "Natural White Oak Woodgrain",
        "nordic": "Nordic Blonde Timber / Sage Matte",
        "minimalist": "Ultra-Matte Charcoal Anti-Fingerprint",
        "industrial": "Smoked Oak & Deep Walnut",
    }
    face_finish = finish_map.get(style, "Natural White Oak Woodgrain")
    carcase_material = "16mm Moisture Resistant (HMR) White Melamine"
    back_material = "6mm White HMR MDF Backing"
    door_material = f"18mm E0 MR MDF — {face_finish}"

    part_counter = 1

    for idx, cab in enumerate(cabinets, start=1):
        cab_ref = f"CAB-{idx:02d}"
        cab_type = cab.get("cabinet_type", "base_600")
        w = float(cab.get("width_mm", 600.0))
        h = float(cab.get("height_mm", 850.0))
        d = float(cab.get("depth_mm", 600.0))

        if "wall" in cab_type:
            # Overhead wall cabinet
            panels = [
                ("Left Side Gable", carcase_material, h, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Right Side Gable", carcase_material, h, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Top Carcase Panel", carcase_material, w - 32.0, d, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Bottom Carcase Panel", carcase_material, w - 32.0, d, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Adjustable Shelf", carcase_material, w - 36.0, d - 20.0, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Back Panel", back_material, h - 32.0, w - 32.0, 6.0, 1, "Unfinished", "Vertical"),
                ("Door Face", door_material, h - 4.0, w - 4.0, 18.0, 1, "1mm All 4 Edges", "Vertical"),
            ]
        elif "tall" in cab_type:
            # Tall pantry cabinet
            panels = [
                ("Left Side Gable", carcase_material, h, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Right Side Gable", carcase_material, h, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Top Carcase Panel", carcase_material, w - 32.0, d, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Bottom Carcase Panel", carcase_material, w - 32.0, d, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Fixed Mid Shelf", carcase_material, w - 32.0, d - 10.0, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Adjustable Shelves", carcase_material, w - 36.0, d - 20.0, 16.0, 3, "1mm Front Edge", "Horizontal"),
                ("Back Panel", back_material, h - 32.0, w - 32.0, 6.0, 1, "Unfinished", "Vertical"),
                ("Upper Door Face", door_material, round((h - 8.0) * 0.45), w - 4.0, 18.0, 1, "1mm All 4 Edges", "Vertical"),
                ("Lower Door Face", door_material, round((h - 8.0) * 0.55), w - 4.0, 18.0, 1, "1mm All 4 Edges", "Vertical"),
                ("Toe-Kick Plinth", "16mm Black HMR Particleboard", 150.0, w, 16.0, 1, "1mm Top Edge", "Horizontal"),
            ]
        else:
            # Base floor cabinet
            panels = [
                ("Left Side Gable", carcase_material, h - 150.0, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Right Side Gable", carcase_material, h - 150.0, d, 16.0, 1, "1mm Front Edge", "Vertical"),
                ("Bottom Carcase Panel", carcase_material, w - 32.0, d, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Top Stretcher Rails", carcase_material, w - 32.0, 100.0, 16.0, 2, "1mm Front Edge", "Horizontal"),
                ("Adjustable Shelf", carcase_material, w - 36.0, d - 30.0, 16.0, 1, "1mm Front Edge", "Horizontal"),
                ("Back Panel", back_material, (h - 150.0) - 32.0, w - 32.0, 6.0, 1, "Unfinished", "Vertical"),
                ("Door Face", door_material, (h - 150.0) - 4.0, w - 4.0, 18.0, 1, "1mm All 4 Edges", "Vertical"),
                ("Toe-Kick Plinth", "16mm Black HMR Particleboard", 150.0, w, 16.0, 1, "1mm Top Edge", "Horizontal"),
            ]

        for p_name, mat, length, width, thick, qty, edge, grain in panels:
            writer.writerow([
                f"P{part_counter:04d}",
                cab_ref,
                cab_type,
                p_name,
                mat,
                face_finish if "Door" in p_name else "Standard Interior Melamine",
                f"{length:.1f}",
                f"{width:.1f}",
                f"{thick:.1f}",
                qty,
                edge,
                grain
            ])
            part_counter += 1

    return output.getvalue()
