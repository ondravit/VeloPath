"""Build the routing graph: topology from OSM node ids, condition conflation,
degree-2 contraction and geometry simplification."""
from __future__ import annotations

import logging
from collections import defaultdict
from dataclasses import dataclass, field

import numpy as np

from .condition import CONFLATABLE, PROJ, OfficialLayer, conflate_segment
from .elevation import WayElevation, haversine_m
from .model import Condition, ConditionSource, Surface, pack_attr
from .osm_reader import OsmWays
from .profile import normalize_ref

log = logging.getLogger(__name__)

SIMPLIFY_TOLERANCE_M = 1.0


@dataclass
class Piece:
    """A stretch of road with uniform attributes between two graph nodes."""
    u: int                      # start node id (OSM id, or negative synthetic id)
    v: int                      # end node id
    lat: np.ndarray
    lon: np.ndarray
    ele: np.ndarray
    attr: int
    year: int
    fwd: bool                   # u -> v allowed
    bwd: bool                   # v -> u allowed
    length: float
    ascent: float               # in u -> v direction
    descent: float

    def reversed(self) -> "Piece":
        return Piece(self.v, self.u, self.lat[::-1].copy(), self.lon[::-1].copy(), self.ele[::-1].copy(),
                     self.attr, self.year, self.bwd, self.fwd, self.length, self.descent, self.ascent)


@dataclass
class Graph:
    node_lat: np.ndarray        # float64 degrees
    node_lon: np.ndarray
    geoms: list[Piece]
    geom_u: np.ndarray          # compact node index of geometry start
    geom_v: np.ndarray
    stats: dict = field(default_factory=dict)


def _interp_cut(lat, lon, ele, dist, d0, d1):
    """Sub-polyline between distances d0 and d1 (inclusive, interpolated end points)."""
    inner = np.nonzero((dist > d0 + 1e-6) & (dist < d1 - 1e-6))[0]
    lat_out = np.concatenate([[np.interp(d0, dist, lat)], lat[inner], [np.interp(d1, dist, lat)]])
    lon_out = np.concatenate([[np.interp(d0, dist, lon)], lon[inner], [np.interp(d1, dist, lon)]])
    if np.isnan(ele).any():
        ele_out = np.full(len(lat_out), np.nan)
    else:
        ele_out = np.concatenate([[np.interp(d0, dist, ele)], ele[inner], [np.interp(d1, dist, ele)]])
    return lat_out, lon_out, ele_out


def build_pieces(ways: OsmWays, elevation: WayElevation, official: OfficialLayer | None) -> list[Piece]:
    ids = ways.node_ids_np
    off = ways.offsets_np
    uniq, counts = np.unique(ids, return_counts=True)
    is_junction_id = set(uniq[counts > 1].tolist())
    log.info("Topology: %d distinct nodes, %d shared by several ways", len(uniq), len(is_junction_id))

    x_all, y_all = PROJ.transform(ways.lon_np, ways.lat_np)
    if official is not None:
        obx0, oby0, obx1, oby1 = official.bounds
    synthetic = -1
    pieces: list[Piece] = []
    conflated_m = 0.0

    for w in range(len(ways)):
        a, b = int(off[w]), int(off[w + 1])
        prof = ways.profiles[w]
        wid = ids[a:b]
        split_idx = [0] + [i for i in range(1, b - a - 1) if int(wid[i]) in is_junction_id] + [b - a - 1]
        # closed ways / self-touching ways: make sure no piece starts and ends at the same node
        refined = [split_idx[0]]
        for s, e in zip(split_idx[:-1], split_idx[1:]):
            if wid[s] == wid[e] and e - s >= 2:
                refined.append((s + e) // 2)
            refined.append(e)
        split_idx = refined
        lat = ways.lat_np[a:b]
        lon = ways.lon_np[a:b]
        vdist = elevation.vertex_dist[a:b]
        vele = elevation.vertex_ele[a:b]
        refs = normalize_ref(prof.ref)
        fwd = prof.oneway >= 0
        bwd = prof.oneway <= 0

        for s, e in zip(split_idx[:-1], split_idx[1:]):
            if e <= s:
                continue
            seg_lat, seg_lon = lat[s:e + 1], lon[s:e + 1]
            seg_ele = vele[s:e + 1]
            seg_d = vdist[s:e + 1] - vdist[s]
            length = float(seg_d[-1])
            if length < 0.05:
                continue
            u_id, v_id = int(wid[s]), int(wid[e])

            runs = None
            if official is not None and prof.road_class in CONFLATABLE:
                sx, sy = x_all[a + s:a + e + 1], y_all[a + s:a + e + 1]
                if sx.max() >= obx0 - 50 and sx.min() <= obx1 + 50 and sy.max() >= oby0 - 50 and sy.min() <= oby1 + 50:
                    runs = conflate_segment(official, sx, sy, refs)

            if not runs:
                runs_iter = [(0.0, length, -1, 0, -1)]
            else:
                runs_iter = [(r.start_m, r.end_m, r.condition, r.year, r.surface) for r in runs]

            prev_node = u_id
            for k, (d0, d1, cond, year, osurf) in enumerate(runs_iter):
                last = k == len(runs_iter) - 1
                if last:
                    end_node = v_id
                else:
                    end_node = synthetic
                    synthetic -= 1
                if len(runs_iter) == 1:
                    p_lat, p_lon, p_ele = seg_lat.copy(), seg_lon.copy(), seg_ele.copy()
                else:
                    p_lat, p_lon, p_ele = _interp_cut(seg_lat, seg_lon, seg_ele, seg_d, d0, d1)
                surface = prof.surface
                if cond >= 0:
                    condition, source = cond, ConditionSource.OFFICIAL
                    conflated_m += d1 - d0
                    if surface == Surface.UNKNOWN and osurf >= 0:
                        surface = osurf
                elif prof.condition != Condition.UNKNOWN:
                    condition, source, year = int(prof.condition), ConditionSource.OSM_SMOOTHNESS, 0
                else:
                    condition, source, year = int(Condition.UNKNOWN), ConditionSource.NONE, 0
                asc, desc = elevation.ascent_descent(w, float(vdist[s] + d0), float(vdist[s] + d1))
                plen = float(np.sum(haversine_m(p_lat[:-1], p_lon[:-1], p_lat[1:], p_lon[1:])))
                pieces.append(Piece(prev_node, end_node, p_lat, p_lon, p_ele,
                                    pack_attr(prof.road_class, surface, condition, source, prof.dismount),
                                    int(year), fwd, bwd, plen, asc, desc))
                prev_node = end_node

    log.info("Pieces: %d (official condition transferred onto %.0f km)", len(pieces), conflated_m / 1000)
    return pieces


def contract(pieces: list[Piece]) -> list[Piece]:
    """Merge chains of pieces through degree-2 nodes with identical attributes."""
    incid: dict[int, list[tuple[int, int]]] = defaultdict(list)
    for i, p in enumerate(pieces):
        incid[p.u].append((i, 0))
        incid[p.v].append((i, 1))

    def mergeable(node: int) -> bool:
        inc = incid[node]
        if len(inc) != 2 or inc[0][0] == inc[1][0]:
            return False
        (i, ei), (j, ej) = inc
        p, q = pieces[i], pieces[j]
        if p.attr != q.attr or p.year != q.year:
            return False
        # orient p so that it ends at node and q so that it starts at node
        pf, pb = (p.fwd, p.bwd) if ei == 1 else (p.bwd, p.fwd)
        qf, qb = (q.fwd, q.bwd) if ej == 0 else (q.bwd, q.fwd)
        return pf == qf and pb == qb

    def other(node: int, idx: int) -> tuple[int, int]:
        a, b = incid[node]
        return b if a[0] == idx else a

    used = np.zeros(len(pieces), dtype=bool)
    out: list[Piece] = []
    for start in range(len(pieces)):
        if used[start]:
            continue
        used[start] = True
        chain: list[Piece] = [pieces[start]]
        head_idx = tail_idx = start
        # forward
        node = chain[-1].v
        while node != chain[0].u and mergeable(node):
            j, end = other(node, tail_idx)
            if used[j]:
                break
            used[j] = True
            q = pieces[j] if end == 0 else pieces[j].reversed()
            chain.append(q)
            tail_idx = j
            node = q.v
        # backward
        node = chain[0].u
        while node != chain[-1].v and mergeable(node):
            j, end = other(node, head_idx)
            if used[j]:
                break
            used[j] = True
            q = pieces[j] if end == 1 else pieces[j].reversed()
            chain.insert(0, q)
            head_idx = j
            node = q.u
        out.append(_join(chain))
    log.info("Contraction: %d pieces -> %d geometries", len(pieces), len(out))
    return out


def _join(chain: list[Piece]) -> Piece:
    if len(chain) == 1:
        return chain[0]
    lat = np.concatenate([chain[0].lat] + [c.lat[1:] for c in chain[1:]])
    lon = np.concatenate([chain[0].lon] + [c.lon[1:] for c in chain[1:]])
    ele = np.concatenate([chain[0].ele] + [c.ele[1:] for c in chain[1:]])
    first = chain[0]
    return Piece(first.u, chain[-1].v, lat, lon, ele, first.attr, first.year, first.fwd, first.bwd,
                 sum(c.length for c in chain), sum(c.ascent for c in chain), sum(c.descent for c in chain))


def _douglas_peucker(x: np.ndarray, y: np.ndarray, tol: float) -> np.ndarray:
    n = len(x)
    if n <= 2:
        return np.ones(n, dtype=bool)
    keep = np.zeros(n, dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        dx, dy = x[j] - x[i], y[j] - y[i]
        seg = np.hypot(dx, dy)
        px, py = x[i + 1:j] - x[i], y[i + 1:j] - y[i]
        if seg < 1e-9:
            d = np.hypot(px, py)
        else:
            d = np.abs(px * dy - py * dx) / seg
        k = int(np.argmax(d))
        if d[k] > tol:
            m = i + 1 + k
            keep[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return keep


def simplify(geoms: list[Piece], tol: float = SIMPLIFY_TOLERANCE_M) -> int:
    before = sum(len(g.lat) for g in geoms)
    for g in geoms:
        if len(g.lat) <= 2:
            continue
        x, y = PROJ.transform(g.lon, g.lat)
        keep = _douglas_peucker(np.asarray(x), np.asarray(y), tol)
        g.lat, g.lon, g.ele = g.lat[keep], g.lon[keep], g.ele[keep]
    after = sum(len(g.lat) for g in geoms)
    log.info("Simplification: %d -> %d vertices", before, after)
    return after


def finalize(geoms: list[Piece]) -> Graph:
    node_index: dict[int, int] = {}
    node_lat: list[float] = []
    node_lon: list[float] = []
    gu = np.empty(len(geoms), dtype=np.int64)
    gv = np.empty(len(geoms), dtype=np.int64)
    for i, g in enumerate(geoms):
        for which, nid, la, lo in ((0, g.u, g.lat[0], g.lon[0]), (1, g.v, g.lat[-1], g.lon[-1])):
            idx = node_index.get(nid)
            if idx is None:
                idx = len(node_lat)
                node_index[nid] = idx
                node_lat.append(float(la))
                node_lon.append(float(lo))
            if which == 0:
                gu[i] = idx
            else:
                gv[i] = idx
    return Graph(np.array(node_lat), np.array(node_lon), geoms, gu, gv)


def largest_component_filter(graph: Graph, min_nodes: int = 30) -> Graph:
    """Drop tiny disconnected islands (private estates, mapping errors)."""
    n = len(graph.node_lat)
    parent = np.arange(n)

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root

    for u, v in zip(graph.geom_u, graph.geom_v):
        ru, rv = find(int(u)), find(int(v))
        if ru != rv:
            parent[ru] = rv
    roots = np.array([find(i) for i in range(n)])
    uniq, counts = np.unique(roots, return_counts=True)
    size = dict(zip(uniq.tolist(), counts.tolist()))
    keep_geom = [i for i in range(len(graph.geoms)) if size[int(roots[graph.geom_u[i]])] >= min_nodes]
    dropped = len(graph.geoms) - len(keep_geom)
    geoms = [graph.geoms[i] for i in keep_geom]
    log.info("Components: %d, dropped %d geometries in islands < %d nodes", len(uniq), dropped, min_nodes)
    return finalize(geoms)
