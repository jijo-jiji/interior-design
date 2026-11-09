"""Compares the app's measurements with a tape's.

    python tool/wall_benchmark/evaluate.py backend/projects_db.json truth.csv

The truth file has one row per window or door (see truth-template.csv). Each
quote's openings are matched to the tape's by type and left-to-right order.
"""

from __future__ import annotations

import csv
import json
import statistics
import sys
from collections import defaultdict

FIELDS = (
    ("left_mm", "distance_from_left_mm", "from left"),
    ("from_floor_mm", "distance_from_floor_mm", "from floor"),
    ("width_mm", "width_mm", "width"),
    ("height_mm", "height_mm", "height"),
)


def load_truth(path: str) -> dict[str, dict]:
    walls: dict[str, dict] = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            qid = row["quote_id"].strip()
            wall = walls.setdefault(qid, {
                "view": row.get("view", "").strip() or "-",
                "openings": [],
            })
            if row.get("type", "").strip():
                wall["openings"].append({
                    "type": row["type"].strip(),
                    **{k: float(row[k]) for k, _, _ in FIELDS},
                })
    return walls


def main(db_path: str, truth_path: str) -> int:
    with open(db_path, encoding="utf-8") as f:
        db = json.load(f)
    projects = db if isinstance(db, dict) else {p["quote_id"]: p for p in db}
    truth = load_truth(truth_path)

    errors: dict[str, list[float]] = defaultdict(list)
    missing = []
    for qid, wall in truth.items():
        project = projects.get(qid)
        if project is None:
            missing.append(qid)
            continue
        capture = project.get("capture") or {}
        tilt = capture.get("tilt_deg") or {}
        print(f"\n{qid}  ({wall['view']})  lens: {capture.get('focal_source', '-')}"
              f"  tilt: roll {tilt.get('roll', '-')} deg, pitch {tilt.get('pitch', '-')} deg")
        by_type: dict[str, list[dict]] = defaultdict(list)
        for o in project.get("obstacles", []):
            by_type[o["type"]].append(o)
        for kind in by_type:
            by_type[kind].sort(key=lambda o: o["distance_from_left_mm"])
        seen: dict[str, int] = defaultdict(int)
        for t in sorted(wall["openings"], key=lambda o: o["left_mm"]):
            i = seen[t["type"]]
            seen[t["type"]] += 1
            app = by_type[t["type"]][i] if i < len(by_type[t["type"]]) else None
            if app is None:
                print(f"  {t['type']} {i + 1}: not marked in the app")
                continue
            parts = []
            for tk, ak, label in FIELDS:
                err = app[ak] - t[tk]
                errors[label].append(abs(err))
                errors[f"view: {wall['view']}"].append(abs(err))
                parts.append(f"{label} {err:+.0f}")
            print(f"  {t['type']} {i + 1}: " + ", ".join(parts) + " mm")

    if missing:
        print(f"\nNot in the database: {', '.join(missing)}")
    if not errors:
        print("\nNothing to compare.")
        return 1
    print("\nSummary (absolute error, mm):")
    for label, values in errors.items():
        print(f"  {label:<20} median {statistics.median(values):6.0f}   "
              f"worst {max(values):6.0f}   ({len(values)} values)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
