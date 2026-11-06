"""Backend half of the pricing contract.

The figures live in test/fixtures/pricing_cases.json and are shared with
test/pricing_contract_test.dart. The app shows the client a price; this engine
prints the one they sign. If the two drift apart, one of the two suites fails.

Run:  python backend/test_pricing_contract.py     (or via pytest)
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.catalog import default_catalog  # noqa: E402
from backend.main import QuoteRequest, price_quote  # noqa: E402

FIXTURE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test", "fixtures", "pricing_cases.json",
)

TOLERANCE = 0.01


def load_cases() -> list[dict]:
    with open(FIXTURE, "r", encoding="utf-8") as f:
        return json.load(f)["cases"]


def price_case(case: dict):
    request = QuoteRequest(
        wall={"width_mm": 4000, "height_mm": 2700, "depth_mm": 150},
        placed_cabinets=case["placed_cabinets"],
        obstacles=case["obstacles"],
        style_archetype=case["style_archetype"],
        benchtop_material=case["benchtop_material"],
    )
    # price_quote is pure: no database write, no PDF.
    # Always the sample catalogue (not whatever has been edited on this
    # machine), so the figures stay comparable with the other two engines.
    _, subtotal, gst, total = price_quote(request, default_catalog())
    return subtotal, gst, total


def test_pricing_matches_contract():
    failures = []

    for case in load_cases():
        subtotal, gst, total = price_case(case)
        expected = case["expected"]

        for label, actual, want in (
            ("subtotal", subtotal, expected["subtotal"]),
            ("gst", gst, expected["gst"]),
            ("total_price", total, expected["total_price"]),
        ):
            if abs(actual - want) > TOLERANCE:
                failures.append(
                    f"{case['name']}: {label} was {actual:.2f}, contract says {want:.2f}"
                )

    assert not failures, (
        "Backend pricing no longer matches the agreed contract. The mobile app "
        "would show a different number than the signed PDF:\n  "
        + "\n  ".join(failures)
    )


def test_benchtop_only_covers_base_and_corner_run():
    """Wall and tall units carry no benchtop — the metre count must ignore them."""
    from backend.catalog import benchtop_metres

    metres = benchtop_metres(default_catalog(), [
        ("base_800", 800),    # 0.80
        ("wall_600", 600),    # ignored
        ("tall_600", 600),    # ignored
        ("corner_900", 900),  # 1.80 (both wings)
    ])
    assert abs(metres - 2.6) < 0.001, f"expected 2.6 lm, got {metres}"


if __name__ == "__main__":
    test_pricing_matches_contract()
    test_benchtop_only_covers_base_and_corner_run()
    cases = load_cases()
    print(f"[PASS] pricing contract — {len(cases)} cases match on both sides")
    for case in cases:
        subtotal, gst, total = price_case(case)
        print(f"  {case['name']:<38} subtotal={subtotal:>9.2f} total={total:>9.2f}")
