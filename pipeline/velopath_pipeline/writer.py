"""Binary graph writer (format documented in docs/graph-format.md)."""
from __future__ import annotations

import json
import logging
import struct

import numpy as np

from .graph import Graph

log = logging.getLogger(__name__)

MAGIC = b"VPGRAPH1"
FORMAT_VERSION = 1
HEADER_SIZE = 512
E7 = 1e7
ELE_MISSING = -32768
REVERSED_BIT = 0x8000_0000

GRID_CELL_LAT = 0.005     # ~556 m
GRID_CELL_LON = 0.0075    # ~535 m at 50°N

SECTIONS = [
    "node_lat", "node_lon", "first_edge", "edge_target", "edge_geom",
    "geom_length", "geom_attr", "geom_year", "geom_ascent", "geom_descent",
    "geom_first_coord", "coord_lat", "coord_lon", "coord_ele",
    "grid_cell_start", "grid_items", "metadata", "geom_node_u", "geom_node_v",
]


def _e7(a) -> np.ndarray:
    return np.round(np.asarray(a, dtype=np.float64) * E7).astype(np.int32)


def build_arrays(g: Graph) -> dict[str, np.ndarray]:
    n = len(g.node_lat)
    geoms = g.geoms
    n_geoms = len(geoms)

    # --- directed edges in CSR order ---------------------------------------------------
    src, dst, ref = [], [], []
    for i, p in enumerate(geoms):
        u, v = int(g.geom_u[i]), int(g.geom_v[i])
        if p.fwd:
            src.append(u); dst.append(v); ref.append(i)
        if p.bwd:
            src.append(v); dst.append(u); ref.append(i | REVERSED_BIT)
    src = np.array(src, dtype=np.int64)
    dst = np.array(dst, dtype=np.uint32)
    ref = np.array(ref, dtype=np.uint32)
    order = np.argsort(src, kind="stable")
    src, dst, ref = src[order], dst[order], ref[order]
    first_edge = np.zeros(n + 1, dtype=np.uint32)
    np.add.at(first_edge, src + 1, 1)
    first_edge = np.cumsum(first_edge).astype(np.uint32)

    # --- geometry ------------------------------------------------------------------------
    counts = np.array([len(p.lat) for p in geoms], dtype=np.int64)
    first_coord = np.concatenate([[0], np.cumsum(counts)]).astype(np.uint32)
    lat = np.concatenate([p.lat for p in geoms])
    lon = np.concatenate([p.lon for p in geoms])
    ele = np.concatenate([p.ele for p in geoms])
    ele_dm = np.where(np.isnan(ele), ELE_MISSING, np.clip(np.round(ele * 10), -32767, 32767)).astype(np.int16)

    arrays = {
        "node_lat": _e7(g.node_lat),
        "node_lon": _e7(g.node_lon),
        "first_edge": first_edge,
        "edge_target": dst,
        "edge_geom": ref,
        "geom_length": np.array([p.length for p in geoms], dtype=np.float32),
        "geom_attr": np.array([p.attr for p in geoms], dtype=np.uint16),
        "geom_year": np.array([max(0, min(255, p.year - 2000)) if p.year else 0 for p in geoms], dtype=np.uint8),
        "geom_ascent": np.clip(np.round(np.array([p.ascent for p in geoms]) * 10), 0, 65535).astype(np.uint16),
        "geom_descent": np.clip(np.round(np.array([p.descent for p in geoms]) * 10), 0, 65535).astype(np.uint16),
        "geom_first_coord": first_coord,
        "coord_lat": _e7(lat),
        "coord_lon": _e7(lon),
        "coord_ele": ele_dm,
        "geom_node_u": g.geom_u.astype(np.uint32),
        "geom_node_v": g.geom_v.astype(np.uint32),
    }

    # --- spatial grid ---------------------------------------------------------------------
    min_lat, max_lat = float(lat.min()), float(lat.max())
    min_lon, max_lon = float(lon.min()), float(lon.max())
    o_lat = np.floor(min_lat / GRID_CELL_LAT) * GRID_CELL_LAT
    o_lon = np.floor(min_lon / GRID_CELL_LON) * GRID_CELL_LON
    rows = int(np.floor((max_lat - o_lat) / GRID_CELL_LAT)) + 1
    cols = int(np.floor((max_lon - o_lon) / GRID_CELL_LON)) + 1
    geom_of_coord = np.repeat(np.arange(n_geoms), counts)
    # segment = consecutive coords within the same geometry
    same = geom_of_coord[:-1] == geom_of_coord[1:]
    a_lat, b_lat = lat[:-1][same], lat[1:][same]
    a_lon, b_lon = lon[:-1][same], lon[1:][same]
    seg_geom = geom_of_coord[:-1][same]
    r0 = np.floor((np.minimum(a_lat, b_lat) - o_lat) / GRID_CELL_LAT).astype(np.int64)
    r1 = np.floor((np.maximum(a_lat, b_lat) - o_lat) / GRID_CELL_LAT).astype(np.int64)
    c0 = np.floor((np.minimum(a_lon, b_lon) - o_lon) / GRID_CELL_LON).astype(np.int64)
    c1 = np.floor((np.maximum(a_lon, b_lon) - o_lon) / GRID_CELL_LON).astype(np.int64)
    pairs_cell, pairs_geom = [], []
    simple = (r0 == r1) & (c0 == c1)
    pairs_cell.append(r0[simple] * cols + c0[simple])
    pairs_geom.append(seg_geom[simple])
    for k in np.nonzero(~simple)[0]:
        for r in range(r0[k], r1[k] + 1):
            for c in range(c0[k], c1[k] + 1):
                pairs_cell.append(np.array([r * cols + c]))
                pairs_geom.append(np.array([seg_geom[k]]))
    cell = np.concatenate(pairs_cell)
    gid = np.concatenate(pairs_geom)
    key = np.unique(cell * (n_geoms + 1) + gid)
    cell = key // (n_geoms + 1)
    gid = key % (n_geoms + 1)
    cell_start = np.zeros(rows * cols + 1, dtype=np.uint32)
    np.add.at(cell_start, cell + 1, 1)
    arrays["grid_cell_start"] = np.cumsum(cell_start).astype(np.uint32)
    arrays["grid_items"] = gid.astype(np.uint32)
    arrays["_grid"] = (rows, cols, o_lat, o_lon)
    arrays["_bbox"] = (min_lat, min_lon, max_lat, max_lon)
    return arrays


def write_graph(path: str, g: Graph, metadata: dict) -> dict:
    arrays = build_arrays(g)
    rows, cols, o_lat, o_lon = arrays.pop("_grid")
    bbox = arrays.pop("_bbox")
    arrays["metadata"] = np.frombuffer(json.dumps(metadata, ensure_ascii=False, indent=1).encode("utf-8"), dtype=np.uint8)

    blobs = []
    offset = HEADER_SIZE
    table = []
    for name in SECTIONS:
        data = np.ascontiguousarray(arrays[name]).tobytes()
        pad = (-offset) % 8
        offset += pad
        table.append((offset, len(data)))
        blobs.append((pad, data))
        offset += len(data)

    header = bytearray(HEADER_SIZE)
    struct.pack_into("<8sII", header, 0, MAGIC, FORMAT_VERSION, HEADER_SIZE)
    struct.pack_into("<IIIIIII", header, 16,
                     len(g.node_lat), len(arrays["edge_target"]), len(g.geoms), len(arrays["coord_lat"]),
                     rows, cols, len(arrays["grid_items"]))
    struct.pack_into("<iiii", header, 44, *(int(round(v * E7)) for v in bbox))
    struct.pack_into("<iiii", header, 60, int(round(o_lat * E7)), int(round(o_lon * E7)),
                     int(round(GRID_CELL_LAT * E7)), int(round(GRID_CELL_LON * E7)))
    struct.pack_into("<I", header, 76, len(SECTIONS))
    for i, (off, ln) in enumerate(table):
        struct.pack_into("<QQ", header, 80 + 16 * i, off, ln)

    with open(path, "wb") as f:
        f.write(header)
        for pad, data in blobs:
            f.write(b"\0" * pad)
            f.write(data)
    size = offset
    info = {
        "nodes": len(g.node_lat), "edges": int(len(arrays["edge_target"])), "geoms": len(g.geoms),
        "coords": int(len(arrays["coord_lat"])), "grid": [rows, cols], "grid_items": int(len(arrays["grid_items"])),
        "bytes": size,
    }
    log.info("Wrote %s: %s", path, info)
    return info
