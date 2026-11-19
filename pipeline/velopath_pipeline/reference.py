"""Reference reader + router for the binary graph.

This is a straightforward Python port of the Swift engine (VeloCore).  It is used to
validate graph files and to generate the fixtures the Swift unit tests compare against,
so that both implementations are guaranteed to produce the same routes.
"""
from __future__ import annotations

import heapq
import json
import math
import struct
from dataclasses import dataclass

import numpy as np

from .writer import HEADER_SIZE, MAGIC, REVERSED_BIT, SECTIONS

# ---- cost model (mirror of VeloCore/Sources/VeloCore/Routing/CostModel.swift) ----------
CLASS_FACTOR = [1.0, 1.15, 1.08, 1.25, 1.2, 1.05, 1.0, 1.0, 1.06, 1.3, 1.6, 1.3, 1.3, 1.3, 1.3, 1.3]
CLASS_FACTOR_AVOID_MAIN = {8: 1.25, 9: 2.5, 10: 4.0}
SURFACE_K = [0.0, 0.25, 0.4, 1.2, 2.5, 0.12, 2.0, 0.25]
CONDITION_K = [0.0, 0.06, 0.25, 0.75, 1.6, 2.8, 0.25, 0.25]
DISMOUNT_FACTOR = 3.0


def cost_table(quality: float, avoid_main_roads: bool) -> np.ndarray:
    """Cost multiplier for every 13-bit attribute code (class|surface|condition|source|dismount)."""
    q = min(1.0, max(0.0, quality))
    table = np.empty(1 << 13, dtype=np.float64)
    for code in range(1 << 13):
        rc = code & 0xF
        surf = (code >> 4) & 0x7
        cond = (code >> 7) & 0x7
        dismount = bool(code & (1 << 12))
        f = CLASS_FACTOR[rc]
        if avoid_main_roads and rc in CLASS_FACTOR_AVOID_MAIN:
            f = CLASS_FACTOR_AVOID_MAIN[rc]
        f *= 1.0 + (0.3 + 0.7 * q) * SURFACE_K[surf]
        f *= 1.0 + q * CONDITION_K[cond]
        if dismount:
            f *= DISMOUNT_FACTOR
        table[code] = f
    return table


@dataclass
class GraphFile:
    n: int
    e: int
    g: int
    c: int
    arrays: dict
    meta: dict
    grid: tuple

    @classmethod
    def load(cls, path: str) -> "GraphFile":
        b = open(path, "rb").read()
        magic, version, hsize = struct.unpack_from("<8sII", b, 0)
        assert magic == MAGIC and hsize == HEADER_SIZE, "not a VPGRAPH1 file"
        n, e, g, c, rows, cols, items = struct.unpack_from("<7I", b, 16)
        grid = struct.unpack_from("<4i", b, 60) + (rows, cols)
        count = struct.unpack_from("<I", b, 76)[0]
        dtypes = {
            "node_lat": "<i4", "node_lon": "<i4", "first_edge": "<u4", "edge_target": "<u4", "edge_geom": "<u4",
            "geom_length": "<f4", "geom_attr": "<u2", "geom_year": "u1", "geom_ascent": "<u2", "geom_descent": "<u2",
            "geom_first_coord": "<u4", "coord_lat": "<i4", "coord_lon": "<i4", "coord_ele": "<i2",
            "grid_cell_start": "<u4", "grid_items": "<u4", "metadata": "u1", "geom_node_u": "<u4", "geom_node_v": "<u4",
        }
        arrays = {}
        for i in range(count):
            off, ln = struct.unpack_from("<QQ", b, 80 + 16 * i)
            name = SECTIONS[i]
            dt = np.dtype(dtypes[name])
            arrays[name] = np.frombuffer(b, dt, ln // dt.itemsize, off)
        meta = json.loads(bytes(arrays["metadata"]).decode("utf-8"))
        return cls(n, e, g, c, arrays, meta, grid)

    # -- geometry helpers -------------------------------------------------------------
    def geom_coords(self, gi: int) -> np.ndarray:
        a = self.arrays
        s, t = a["geom_first_coord"][gi], a["geom_first_coord"][gi + 1]
        return np.column_stack([a["coord_lat"][s:t] / 1e7, a["coord_lon"][s:t] / 1e7])


def _equirect(lat1, lon1, lat2, lon2):
    # fast distance used by the heuristic; must never exceed the true path length
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6371008.8 * math.hypot(x, y) * 0.995


@dataclass
class Snap:
    geom: int
    seg: int
    t: float
    along: float     # metres from geometry start
    lat: float
    lon: float
    dist: float


def snap(gf: GraphFile, lat: float, lon: float, max_dist: float = 400.0) -> Snap | None:
    """Nearest point on the network (same algorithm as Router.snap in Swift)."""
    a = gf.arrays
    o_lat, o_lon, c_lat, c_lon, rows, cols = gf.grid
    o_lat, o_lon, c_lat, c_lon = o_lat / 1e7, o_lon / 1e7, c_lat / 1e7, c_lon / 1e7
    kx = math.cos(math.radians(lat)) * 111320.0
    ky = 110574.0
    cell_m = min(c_lat * ky, c_lon * kx)
    r = int(math.floor((lat - o_lat) / c_lat))
    c = int(math.floor((lon - o_lon) / c_lon))
    best = None
    visited = set()
    ring = 0
    while True:
        for rr in range(r - ring, r + ring + 1):
            for cc in range(c - ring, c + ring + 1):
                if ring > 0 and abs(rr - r) != ring and abs(cc - c) != ring:
                    continue
                if not (0 <= rr < rows and 0 <= cc < cols):
                    continue
                k = rr * cols + cc
                for gi in a["grid_items"][a["grid_cell_start"][k]:a["grid_cell_start"][k + 1]].tolist():
                    if gi in visited:
                        continue
                    visited.add(gi)
                    pts = gf.geom_coords(gi)
                    x = (pts[:, 1] - lon) * kx
                    y = (pts[:, 0] - lat) * ky
                    ax, ay, bx, by = x[:-1], y[:-1], x[1:], y[1:]
                    dx, dy = bx - ax, by - ay
                    l2 = dx * dx + dy * dy
                    t = np.where(l2 > 0, np.clip(-(ax * dx + ay * dy) / np.where(l2 > 0, l2, 1), 0, 1), 0)
                    d = np.hypot(ax + t * dx, ay + t * dy)
                    j = int(np.argmin(d))
                    if best is None or d[j] < best[0]:
                        best = (float(d[j]), gi, j, float(t[j]))
        covered = ring * cell_m
        if best is not None and best[0] <= covered:
            break
        if covered > max_dist:
            break
        ring += 1
    if best is None or best[0] > max_dist:
        return None
    d, gi, k, t = best
    pts = gf.geom_coords(gi)
    seglens = [_hav(pts[i, 0], pts[i, 1], pts[i + 1, 0], pts[i + 1, 1]) for i in range(len(pts) - 1)]
    along = sum(seglens[:k]) + t * seglens[k]
    total = sum(seglens)
    along = along / total * float(a["geom_length"][gi]) if total > 0 else 0.0
    la = pts[k, 0] + t * (pts[k + 1, 0] - pts[k, 0])
    lo = pts[k, 1] + t * (pts[k + 1, 1] - pts[k, 1])
    return Snap(gi, k, t, along, float(la), float(lo), d)


def _hav(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(min(1.0, h)))


def route(gf: GraphFile, src: Snap, dst: Snap, table: np.ndarray):
    """A* from snapped source to snapped target. Returns (cost, list of (geom, reversed, from_m, to_m))."""
    a = gf.arrays
    first, target, gref = a["first_edge"], a["edge_target"], a["edge_geom"]
    glen, gattr = a["geom_length"], a["geom_attr"]
    nlat, nlon = a["node_lat"], a["node_lon"]
    gu, gv = a["geom_node_u"], a["geom_node_v"]
    tlat, tlon = dst.lat, dst.lon

    def allowed(gi):
        """(forward, backward) traversal permissions of geometry gi."""
        u = gu[gi]
        fwd = bwd = False
        for k in range(first[u], first[u + 1]):
            if gref[k] == gi:
                fwd = True
        v = gv[gi]
        for k in range(first[v], first[v + 1]):
            if gref[k] == (gi | REVERSED_BIT):
                bwd = True
        return fwd, bwd

    def h(node):
        return _equirect(nlat[node] / 1e7, nlon[node] / 1e7, tlat, tlon)

    best_total = math.inf
    best_path = None
    sf, sb = allowed(src.geom)
    tf, tb = allowed(dst.geom)
    cs = table[gattr[src.geom] & 0x1FFF]
    ct = table[gattr[dst.geom] & 0x1FFF]
    L_s, L_t = float(glen[src.geom]), float(glen[dst.geom])

    # same geometry, direct
    if src.geom == dst.geom:
        if dst.along >= src.along and sf:
            best_total = (dst.along - src.along) * cs
            best_path = [(src.geom, False, src.along, dst.along)]
        elif dst.along < src.along and sb:
            best_total = (src.along - dst.along) * cs
            best_path = [(src.geom, True, src.along, dst.along)]

    g = {}
    parent = {}
    heap = []
    if sf:
        node = int(gv[src.geom]); c = (L_s - src.along) * cs
        g[node] = c; parent[node] = ("start", False); heapq.heappush(heap, (c + h(node), node))
    if sb:
        node = int(gu[src.geom]); c = src.along * cs
        if c < g.get(node, math.inf):
            g[node] = c; parent[node] = ("start", True); heapq.heappush(heap, (c + h(node), node))
    closed = set()
    target_entries = {}
    if tf:
        target_entries[int(gu[dst.geom])] = (dst.along * ct, False)
    if tb:
        n_ = int(gv[dst.geom]); c = (L_t - dst.along) * ct
        if c < target_entries.get(n_, (math.inf,))[0]:
            target_entries[n_] = (c, True)
    expanded = 0
    while heap:
        f, u = heapq.heappop(heap)
        if f >= best_total:
            break
        if u in closed:
            continue
        closed.add(u)
        expanded += 1
        gu_ = g[u]
        if u in target_entries:
            c, rev = target_entries[u]
            if gu_ + c < best_total:
                best_total = gu_ + c
                best_path = ("node", u, rev)
        for k in range(first[u], first[u + 1]):
            v = int(target[k]); ref = int(gref[k]); gi = ref & 0x7FFFFFFF
            nc = gu_ + float(glen[gi]) * table[gattr[gi] & 0x1FFF]
            if nc < g.get(v, math.inf):
                g[v] = nc; parent[v] = (u, ref)
                heapq.heappush(heap, (nc + h(v), v))
    if best_path is None:
        return None, [], expanded
    if isinstance(best_path, list):
        return best_total, best_path, expanded
    _, u, rev = best_path
    legs = [(dst.geom, rev, (0.0 if not rev else L_t), dst.along)]
    while True:
        p = parent[u]
        if p[0] == "start":
            srev = p[1]
            legs.append((src.geom, srev, src.along, 0.0 if srev else L_s))
            break
        prev, ref = p
        gi = ref & 0x7FFFFFFF
        rev_ = bool(ref & REVERSED_BIT)
        legs.append((gi, rev_, float(glen[gi]) if rev_ else 0.0, 0.0 if rev_ else float(glen[gi])))
        u = prev
    legs.reverse()
    return best_total, legs, expanded
