"""The catalogue: every price, size and pricing rule, kept as data.

Before this module the same tables were typed into the server, the Dart app,
the Studio and the layout generator, and a size nobody had typed in was priced
at a flat RM 300. Now:

* One document (a ``Catalog``) holds the fixed modules and their prices, the
  rules that price any other width, finishes, benchtops, labour, tax and the
  layout generator's sizes and design rules.
* ``CatalogStore`` keeps the current catalogue on disk and a copy of every
  version. A quote records the version it was priced with, so the server can
  price a quote the tablet made offline with the very same numbers.
* The seed is ``assets/catalog/default_catalog.json``, also embedded in the
  sales app and imported by the Studio, so there is one source for the sample
  data.

Pricing (the same in the server, the sales app and the Studio; the shared
cases in ``test/fixtures/pricing_cases.json`` keep them honest):

    unit price = module price                       if the type is a fixed module
               = at_ref + (width - ref_width) / 100 * per_100mm   if its family has a rule
               = unknown_module_price               otherwise
    then x the finish multiplier, rounded to the sen.
"""

from __future__ import annotations

import hmac
import json
import os
import re
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

__all__ = [
    "Catalog",
    "CatalogConflict",
    "CatalogStore",
    "ValidationError",
    "admin_key_ok",
    "default_catalog",
]

BACKEND_DIR = Path(__file__).resolve().parent
DEFAULT_PATH = BACKEND_DIR.parent / "assets" / "catalog" / "default_catalog.json"

_TYPE = r"^[a-z][a-z0-9_]*$"


# ─── Document ───────────────────────────────────────────────────────────────


class _Strict(BaseModel):
    # A misspelt key is an error, not a silently ignored edit.
    model_config = ConfigDict(extra="forbid")


class Tax(_Strict):
    label: str = Field(min_length=1, max_length=12)
    rate: float = Field(ge=0, le=0.5)


class StyleOption(_Strict):
    name: str = Field(min_length=1, max_length=60)
    multiplier: float = Field(gt=0, le=5)


class BenchtopOption(_Strict):
    name: str = Field(min_length=1, max_length=60)
    rate_per_m: float = Field(ge=0, le=100000)


class Module(_Strict):
    """A fixed module the apps can add: its size and its price."""

    type: str = Field(pattern=_TYPE, max_length=40)
    label: str = Field(min_length=1, max_length=40)
    section: Literal["cabinet", "appliance"]
    width_mm: float = Field(gt=0, le=5000)
    height_mm: float = Field(gt=0, le=5000)
    depth_mm: float = Field(gt=0, le=5000)
    mount_mm: float = Field(ge=0, le=5000)
    price: float = Field(ge=0, le=1_000_000)


class PriceRule(_Strict):
    at_ref: float = Field(ge=0, le=1_000_000)
    ref_width_mm: float = Field(ge=0, le=5000)
    per_100mm: float = Field(ge=0, le=100000)


class Family(_Strict):
    """How a kind of module is priced and counted (matched by type prefix)."""

    id: str = Field(pattern=_TYPE, max_length=40)
    label: str = Field(min_length=1, max_length=40)
    prefixes: list[str] = Field(min_length=1)
    group: Literal["base", "wall", "tall", "corner"]
    # How the 3D view draws it.
    kind: Literal[
        "base", "drawer", "sink", "hob", "tall", "corner", "wall", "filler",
        "dishwasher", "oven", "fridge", "hood",
    ]
    # width: worktop over its width; fixed: benchtop_m metres; none: no worktop.
    benchtop: Literal["width", "fixed", "none"]
    benchtop_m: float = Field(ge=0, le=20)
    labour: bool
    appliance: bool
    price: PriceRule | None = None


class LayoutRules(_Strict):
    min_sink_to_hob_mm: float = Field(ge=0, le=5000)
    min_hob_side_counter_mm: float = Field(ge=0, le=5000)
    min_sink_to_tall_mm: float = Field(ge=0, le=5000)
    min_filler_mm: float = Field(ge=0, le=500)
    max_filler_mm: float = Field(ge=0, le=500)
    scribe_tolerance_mm: float = Field(ge=0, le=100)
    door_clearance_mm: float = Field(ge=0, le=500)
    window_clearance_mm: float = Field(ge=0, le=500)
    max_sink_shift_from_window_mm: float = Field(ge=0, le=3000)

    @model_validator(mode="after")
    def _filler_range(self) -> "LayoutRules":
        if self.min_filler_mm > self.max_filler_mm:
            raise ValueError("min_filler_mm can't be larger than max_filler_mm")
        return self


Widths = list[float]


class Layout(_Strict):
    """What the layout generator works with."""

    base_door_widths_mm: Widths = Field(min_length=1)
    drawer_widths_mm: Widths = Field(min_length=1)
    sink_widths_mm: Widths = Field(min_length=1)
    hob_widths_mm: Widths = Field(min_length=1)
    tall_width_mm: float = Field(gt=0, le=2000)
    wall_widths_mm: Widths = Field(min_length=1)
    corner_size_mm: float = Field(gt=0, le=2000)
    base_height_mm: float = Field(gt=0, le=2000)
    base_depth_mm: float = Field(gt=0, le=2000)
    counter_height_mm: float = Field(gt=0, le=2000)
    wall_height_mm: float = Field(gt=0, le=2000)
    wall_depth_mm: float = Field(gt=0, le=2000)
    wall_mount_mm: float = Field(ge=0, le=3000)
    tall_height_mm: float = Field(gt=0, le=4000)
    tall_depth_mm: float = Field(gt=0, le=2000)
    rules: LayoutRules

    @model_validator(mode="after")
    def _widths(self) -> "Layout":
        for name in ("base_door_widths_mm", "drawer_widths_mm", "sink_widths_mm",
                     "hob_widths_mm", "wall_widths_mm"):
            values = getattr(self, name)
            if any(not (50 <= w <= 3000) for w in values):
                raise ValueError(f"{name}: every width must be between 50 and 3000 mm")
            if len(set(values)) != len(values):
                raise ValueError(f"{name}: a width is listed twice")
        return self


class Catalog(_Strict):
    schema_version: Literal[1] = 1
    version: int = Field(ge=1)
    updated_at: str | None = None
    name: str = Field(min_length=1, max_length=80)
    # True while the numbers are samples; the apps say so.
    is_placeholder: bool
    currency: str = Field(min_length=3, max_length=3)
    currency_symbol: str = Field(min_length=1, max_length=4)
    tax: Tax
    labour_rate_per_cabinet: float = Field(ge=0, le=100000)
    unknown_module_price: float = Field(ge=0, le=1_000_000)
    obstacle_allowances: dict[str, float]
    style_options: dict[str, StyleOption] = Field(min_length=1)
    benchtop_options: dict[str, BenchtopOption]
    modules: list[Module] = Field(min_length=1)
    families: list[Family]
    layout: Layout

    @model_validator(mode="after")
    def _consistent(self) -> "Catalog":
        types = [m.type for m in self.modules]
        if len(set(types)) != len(types):
            raise ValueError("a module type is listed twice")
        ids = [f.id for f in self.families]
        if len(set(ids)) != len(ids):
            raise ValueError("a family id is listed twice")
        prefixes = [p for f in self.families for p in f.prefixes]
        if len(set(prefixes)) != len(prefixes):
            raise ValueError("a type prefix belongs to two families")
        if any(not p for p in prefixes):
            raise ValueError("a family prefix is empty")
        return self

    # ── lookups ────────────────────────────────────────────────────────────

    def _module_map(self) -> dict[str, Module]:
        return {m.type: m for m in self.modules}

    def module(self, type_: str) -> Module | None:
        return self._module_map().get(type_)

    def family_for(self, type_: str) -> Family | None:
        """The family with the longest prefix of [type_], if any."""
        best: Family | None = None
        best_len = -1
        for fam in self.families:
            for prefix in fam.prefixes:
                if type_.startswith(prefix) and len(prefix) > best_len:
                    best, best_len = fam, len(prefix)
        return best

    def unit_price(self, type_: str, width_mm: float | None = None) -> float:
        """The list price of one module, before the finish multiplier."""
        module = self.module(type_)
        if module is not None:
            return module.price
        fam = self.family_for(type_)
        if fam is not None and fam.price is not None:
            rule = fam.price
            width = width_mm if width_mm else rule.ref_width_mm
            return max(0.0, rule.at_ref + (width - rule.ref_width_mm) / 100.0 * rule.per_100mm)
        return self.unknown_module_price

    def benchtop_metres(self, type_: str, width_mm: float | None) -> float:
        fam = self.family_for(type_)
        if fam is None or fam.benchtop == "none":
            return 0.0
        if fam.benchtop == "fixed":
            return fam.benchtop_m
        width = width_mm
        if not width:
            width = fam.price.ref_width_mm if fam.price else 600.0
        return width / 1000.0

    def carries_labour(self, type_: str) -> bool:
        fam = self.family_for(type_)
        return True if fam is None else fam.labour

    def is_appliance(self, type_: str) -> bool:
        fam = self.family_for(type_)
        return bool(fam and fam.appliance)

    def group_of(self, type_: str) -> str:
        fam = self.family_for(type_)
        return fam.group if fam else "base"

    # ── the document the apps read ─────────────────────────────────────────

    def api_dict(self) -> dict[str, Any]:
        """The document plus the flat maps older clients (and the Studio before
        this module) read: cabinets, styles, style_names, benchtops,
        benchtop_names, gst_rate."""
        doc = self.model_dump(mode="json")
        doc["cabinets"] = {m.type: m.price for m in self.modules}
        doc["styles"] = {k: s.multiplier for k, s in self.style_options.items()}
        doc["style_names"] = {k: s.name for k, s in self.style_options.items()}
        doc["benchtops"] = {k: b.rate_per_m for k, b in self.benchtop_options.items()}
        doc["benchtop_names"] = {k: b.name for k, b in self.benchtop_options.items()}
        doc["gst_rate"] = self.tax.rate
        return doc


# ─── Pricing ────────────────────────────────────────────────────────────────


def _unit(price: float, multiplier: float) -> float:
    return round(price * multiplier, 2)


def price_layout(
    catalog: Catalog,
    cabinets: list[tuple[str, float | None]],
    obstacle_types: list[str],
    style: str,
    benchtop_material: str | None,
) -> tuple[list[dict[str, Any]], float, float, float]:
    """Prices a layout: (lines, subtotal, tax, total).

    [cabinets] are (type, width_mm) pairs. Lines are grouped by type and width
    in first-seen order; each unit price is rounded to the sen before it is
    multiplied, exactly as the sales app and the Studio do.
    """
    style_option = catalog.style_options.get(style)
    multiplier = style_option.multiplier if style_option else 1.0
    style_label = style_option.name if style_option else "Japandi Natural"

    lines: list[dict[str, Any]] = []
    groups: dict[tuple[str, int], list[Any]] = {}
    for type_, width in cabinets:
        key = (type_, round(width or 0))
        if key not in groups:
            groups[key] = [type_, width, 0]
        groups[key][2] += 1

    for (type_, _), (_, width, qty) in groups.items():
        unit = _unit(catalog.unit_price(type_, width), multiplier)
        name = type_.replace("_", " ").title()
        if width and not re.search(r"\d", type_):
            name += f" {round(width)}"  # "Filler Base 75"
        kind = "Appliance" if catalog.is_appliance(type_) else "Cabinet"
        lines.append({
            "description": f"{kind} — {name} ({style_label})",
            "qty": qty,
            "unit_price": unit,
            "total": round(unit * qty, 2),
        })

    labour_count = sum(1 for type_, _ in cabinets if catalog.carries_labour(type_))
    if labour_count > 0:
        rate = catalog.labour_rate_per_cabinet
        lines.append({
            "description": "Installation Labour",
            "qty": labour_count,
            "unit_price": rate,
            "total": round(rate * labour_count, 2),
        })

    metres = round(sum(catalog.benchtop_metres(t, w) for t, w in cabinets), 3)
    benchtop = catalog.benchtop_options.get(benchtop_material or "")
    if benchtop is not None and benchtop.rate_per_m > 0 and metres > 0:
        total = round(benchtop.rate_per_m * metres, 2)
        lines.append({
            "description": (
                f"Benchtop — {benchtop.name} "
                f"({metres:.2f} lm @ {catalog.currency_symbol}{benchtop.rate_per_m:.0f}/m)"
            ),
            "qty": 1,
            "unit_price": total,
            "total": total,
        })

    for obstacle in obstacle_types:
        allowance = catalog.obstacle_allowances.get(obstacle, 0)
        if allowance != 0:
            lines.append({
                "description": f"{obstacle.title()} cutout allowance",
                "qty": 1,
                "unit_price": allowance,
                "total": allowance,
            })

    subtotal = max(0.0, round(sum(line["total"] for line in lines), 2))
    tax = round(subtotal * catalog.tax.rate, 2)
    return lines, subtotal, tax, round(subtotal + tax, 2)


def benchtop_metres(catalog: Catalog, cabinets: list[tuple[str, float | None]]) -> float:
    return round(sum(catalog.benchtop_metres(t, w) for t, w in cabinets), 3)


# ─── Store ──────────────────────────────────────────────────────────────────


def default_catalog() -> Catalog:
    """The sample catalogue shipped with the app (version 1)."""
    return Catalog.model_validate(json.loads(DEFAULT_PATH.read_text(encoding="utf-8")))


class CatalogConflict(Exception):
    """The catalogue changed since the editor loaded it."""


def admin_key_ok(supplied: str | None) -> bool:
    """With CATALOG_ADMIN_KEY set, only a matching key may change the catalogue.
    Unset (the default) leaves editing open, as it was before."""
    required = os.environ.get("CATALOG_ADMIN_KEY")
    if not required:
        return True
    return bool(supplied) and hmac.compare_digest(supplied.encode(), required.encode())


class CatalogStore:
    """The current catalogue and every earlier version, as files.

    ``current.json`` is the live one; ``v0001.json``, ``v0002.json``… are the
    copies a quote can ask for by version.
    """

    def __init__(self, directory: Path | str | None = None) -> None:
        env = os.environ.get("CATALOG_STORE_DIR")
        self.directory = Path(directory or env or BACKEND_DIR / "catalog_store")
        self._lock = threading.Lock()
        self._current: Catalog | None = None

    # -- files --

    def _path(self, version: int) -> Path:
        return self.directory / f"v{version:04d}.json"

    def _write(self, path: Path, catalog: Catalog) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        text = json.dumps(catalog.model_dump(mode="json"), indent=2, ensure_ascii=False)
        fd, tmp = tempfile.mkstemp(dir=self.directory, suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text + "\n")
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)

    # -- reading --

    def current(self) -> Catalog:
        with self._lock:
            if self._current is None:
                self._current = self._load_current()
            return self._current

    def _load_current(self) -> Catalog:
        path = self.directory / "current.json"
        if path.exists():
            try:
                return Catalog.model_validate(json.loads(path.read_text(encoding="utf-8")))
            except (ValueError, ValidationError):
                # A damaged file must not stop the server: fall back to the
                # newest readable version, or the sample.
                for version in sorted(self._version_numbers(), reverse=True):
                    found = self._read_version(version)
                    if found:
                        return found
        seed = default_catalog()
        seed.updated_at = _now()
        self._write(path, seed)
        self._write(self._path(seed.version), seed)
        return seed

    def _version_numbers(self) -> list[int]:
        if not self.directory.exists():
            return []
        return [int(p.stem[1:]) for p in self.directory.glob("v[0-9][0-9][0-9][0-9].json")]

    def _read_version(self, version: int) -> Catalog | None:
        path = self._path(version)
        if not path.exists():
            return None
        try:
            return Catalog.model_validate(json.loads(path.read_text(encoding="utf-8")))
        except (ValueError, ValidationError):
            return None

    def get_version(self, version: int) -> Catalog | None:
        current = self.current()
        if version == current.version:
            return current
        return self._read_version(version)

    def versions(self) -> list[dict[str, Any]]:
        out = []
        for number in sorted(self._version_numbers()):
            found = self._read_version(number)
            if found:
                out.append({
                    "version": number,
                    "updated_at": found.updated_at,
                    "name": found.name,
                    "is_placeholder": found.is_placeholder,
                })
        return out

    # -- writing --

    def save(self, document: dict[str, Any], base_version: int | None) -> Catalog:
        """Validates [document] and stores it as the next version.

        [base_version] is the version the editor started from; if the catalogue
        has moved on since, nothing is saved (CatalogConflict).
        """
        current = self.current()
        if base_version is not None and base_version != current.version:
            raise CatalogConflict(
                f"The catalogue was changed (now version {current.version}). "
                "Reload it and make your change again."
            )
        doc = dict(document)
        doc["version"] = max(current.version, *self._version_numbers() or [0]) + 1
        doc["updated_at"] = _now()
        new = Catalog.model_validate(doc)
        with self._lock:
            self._write(self._path(new.version), new)
            self._write(self.directory / "current.json", new)
            self._current = new
        return new

    def update_legacy(self, payload: dict[str, Any]) -> Catalog:
        """The old partial update ({"cabinets": {type: price}, "styles": …,
        "labour_rate_per_cabinet": …}): applied to the current catalogue."""
        doc = self.current().model_dump(mode="json")
        prices = payload.get("cabinets")
        if isinstance(prices, dict):
            for module in doc["modules"]:
                if module["type"] in prices:
                    module["price"] = float(prices[module["type"]])
        multipliers = payload.get("styles")
        if isinstance(multipliers, dict):
            for key, value in multipliers.items():
                if key in doc["style_options"]:
                    doc["style_options"][key]["multiplier"] = float(value)
        if "labour_rate_per_cabinet" in payload:
            doc["labour_rate_per_cabinet"] = float(payload["labour_rate_per_cabinet"])
        return self.save(doc, None)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
