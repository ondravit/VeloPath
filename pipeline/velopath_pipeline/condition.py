"""Official pavement-condition layers and their conflation onto OSM road segments.

The Královéhradecký kraj layer ("Stav povrchu silnic", Data KHK / NKOD, source ÚDRŽBA
SILNIC Královéhradeckého kraje a.s.) is a set of LineStrings for class II and III roads.
Its geometry is *not* identical to OSM, so instead of merging the two networks (the old
approach, which produced two parallel graphs) we transfer the attribute onto the OSM
segments: every OSM segment of a suitable class is sampled every few metres and each
sample takes the condition of the nearest official line that is close, parallel and –
when OSM knows the road number – carries the same road number.
"""
from __future__ import annotations

import json
import logging
import unicodedata
from dataclasses import dataclass

import numpy as np
import shapely
from pyproj import Transformer

from .model import Condition, RoadClass, Surface
from .profile import normalize_ref

log = logging.getLogger(__name__)

PROJ = Transformer.from_crs("EPSG:4326", "EPSG:32633", always_xy=True)

CONDITION_NAMES = {
    "vyborny": Condition.EXCELLENT,
    "dobry": Condition.GOOD,
    "vyhovujici": Condition.SATISFACTORY,
    "nevyhovujici": Condition.UNSATISFACTORY,
    "havarijni": Condition.EMERGENCY,
    "superhavarijni": Condition.SUPER_EMERGENCY,
}
SURFACE_NAMES = {
    "asfaltobetonovy": Surface.ASPHALT,
    "penetrace": Surface.ASPHALT,
    "dlazba": Surface.SETT,
}

SAMPLE_STEP_M = 10.0
MAX_DIST_REF_MATCH_M = 18.0   # OSM ref equals official road number
MAX_DIST_NO_REF_M = 9.0       # OSM way without ref (e.g. street through a village)
MAX_ANGLE_DEG = 30.0
MIN_RUN_M = 40.0              # shorter condition changes are treated as noise

CONFLATABLE = {RoadClass.SECONDARY, RoadClass.TERTIARY, RoadClass.UNCLASSIFIED,
               RoadClass.RESIDENTIAL, RoadClass.PRIMARY}


def _fold(s: str | None) -> str:
    if not s:
        return ""
    s = unicodedata.normalize("NFKD", s.strip().lower())
    return "".join(ch for ch in s if not unicodedata.combining(ch))


@dataclass
class OfficialLayer:
    lines: np.ndarray           # shapely LineStrings in EPSG:32633
    condition: np.ndarray       # int
    year: np.ndarray            # int (0 = unknown)
    ref: np.ndarray             # normalized road number, str
    surface: np.ndarray         # Surface or -1
    tree: shapely.STRtree
    name: str

    @property
    def bounds(self):
        return shapely.total_bounds(self.lines)


def load_khk_layer(path: str) -> OfficialLayer:
    with open(path, encoding="utf-8") as f:
        fc = json.load(f)
    lines, cond, year, ref, surf = [], [], [], [], []
    skipped = 0
    for feat in fc["features"]:
        p = feat.get("properties") or {}
        g = feat.get("geometry") or {}
        c = CONDITION_NAMES.get(_fold(p.get("stav_sil")))
        if c is None or g.get("type") not in ("LineString", "MultiLineString"):
            skipped += 1
            continue
        parts = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
        for coords in parts:
            if len(coords) < 2:
                continue
            arr = np.asarray(coords, dtype=np.float64)[:, :2]
            x, y = PROJ.transform(arr[:, 0], arr[:, 1])
            lines.append(shapely.linestrings(np.column_stack([x, y])))
            cond.append(int(c))
            try:
                year.append(int(str(p.get("rok") or "0")[:4]))
            except ValueError:
                year.append(0)
            refs = normalize_ref(p.get("ozn_sil"))
            ref.append(next(iter(refs)) if refs else "")
            surf.append(int(SURFACE_NAMES.get(_fold(p.get("typ_povrchu")), -1)))
    lines_arr = np.array(lines, dtype=object)
    log.info("Official condition layer: %d lines (%d skipped)", len(lines_arr), skipped)
    return OfficialLayer(lines_arr, np.array(cond), np.array(year), np.array(ref, dtype=object),
                         np.array(surf), shapely.STRtree(lines_arr), "Královéhradecký kraj")


def _local_direction(x: np.ndarray, y: np.ndarray, d: np.ndarray, at: np.ndarray):
    """Unit direction of a polyline (x, y with cumulative distance d) at distances `at`."""
    i = np.clip(np.searchsorted(d, at, side="right") - 1, 0, len(d) - 2)
    dx = x[i + 1] - x[i]
    dy = y[i + 1] - y[i]
    n = np.hypot(dx, dy) + 1e-12
    return dx / n, dy / n


@dataclass
class ConditionRun:
    start_m: float
    end_m: float
    condition: int
    year: int
    surface: int  # -1 = keep OSM surface


def conflate_segment(layer: OfficialLayer, x: np.ndarray, y: np.ndarray, refs: set[str]) -> list[ConditionRun] | None:
    """Condition runs along one OSM segment (projected coords). None if nothing matched."""
    d = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(x), np.diff(y)))])
    length = d[-1]
    if length < 1.0:
        return None
    n = max(2, int(np.ceil(length / SAMPLE_STEP_M)) + 1)
    at = np.linspace(0, length, n)
    # sample centres of the n-1 intervals so that every sample represents equal length
    centres = (at[:-1] + at[1:]) / 2
    sx = np.interp(centres, d, x)
    sy = np.interp(centres, d, y)
    max_dist = MAX_DIST_REF_MATCH_M if refs else MAX_DIST_NO_REF_M
    pts = shapely.points(sx, sy)
    pi, li = layer.tree.query(pts, predicate="dwithin", distance=max_dist)
    if len(pi) == 0:
        return None
    if refs:
        ok = np.array([layer.ref[j] in refs for j in li])
        pi, li = pi[ok], li[ok]
        if len(pi) == 0:
            return None
    lines = layer.lines[li]
    dist = shapely.distance(pts[pi], lines)
    # direction agreement (undirected)
    proj = shapely.line_locate_point(lines, pts[pi])
    a = shapely.line_interpolate_point(lines, np.maximum(proj - 4.0, 0.0))
    b = shapely.line_interpolate_point(lines, proj + 4.0)
    ax, ay = shapely.get_x(a), shapely.get_y(a)
    bx, by = shapely.get_x(b), shapely.get_y(b)
    lx, ly = bx - ax, by - ay
    ln = np.hypot(lx, ly) + 1e-12
    ux, uy = _local_direction(x, y, d, centres[pi])
    cosang = np.abs((lx * ux + ly * uy) / ln)
    ok = cosang >= np.cos(np.radians(MAX_ANGLE_DEG))
    pi, li, dist = pi[ok], li[ok], dist[ok]
    if len(pi) == 0:
        return None
    # best candidate per sample
    order = np.lexsort((dist, pi))
    pi, li = pi[order], li[order]
    first = np.concatenate([[True], pi[1:] != pi[:-1]])
    best = np.full(n - 1, -1, dtype=np.int64)
    best[pi[first]] = li[first]

    # per-sample attributes; -1 = unmatched
    cond = np.where(best >= 0, layer.condition[np.maximum(best, 0)], -1)
    if (cond >= 0).sum() * SAMPLE_STEP_M < MIN_RUN_M:
        return None
    year = np.where(best >= 0, layer.year[np.maximum(best, 0)], 0)
    surf = np.where(best >= 0, layer.surface[np.maximum(best, 0)], -1)

    # run-length encode and absorb short runs into the longer neighbour
    step = length / (n - 1)
    runs: list[list] = []  # [cond, year, surf, length]
    for c, yv, s in zip(cond, year, surf):
        if runs and runs[-1][0] == c and runs[-1][1] == yv:
            runs[-1][3] += step
        else:
            runs.append([int(c), int(yv), int(s), step])
    changed = True
    while changed and len(runs) > 1:
        changed = False
        k = min(range(len(runs)), key=lambda i: runs[i][3])
        if runs[k][3] >= MIN_RUN_M:
            break
        left = runs[k - 1] if k > 0 else None
        right = runs[k + 1] if k + 1 < len(runs) else None
        target = left if (right is None or (left is not None and left[3] >= right[3])) else right
        target[3] += runs[k][3]
        del runs[k]
        # merge equal neighbours
        merged = [runs[0]]
        for r in runs[1:]:
            if r[0] == merged[-1][0] and r[1] == merged[-1][1]:
                merged[-1][3] += r[3]
            else:
                merged.append(r)
        runs = merged
        changed = True

    out: list[ConditionRun] = []
    pos = 0.0
    for c, yv, s, ln_ in runs:
        out.append(ConditionRun(pos, min(length, pos + ln_), c, yv, s))
        pos += ln_
    out[-1].end_m = length
    if all(r.condition < 0 for r in out):
        return None
    return out
