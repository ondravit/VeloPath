"""Elevation from Copernicus DEM GLO-30 tiles (1°x1° GeoTIFFs, EPSG:4326).

Tile naming: Copernicus_DSM_COG_10_N50_00_E015_00_DEM.tif covers lat 50..51, lon 15..16.

GLO-30 is a surface model (DSM): forest canopy and single-pixel noise would inflate the
climbing totals.  Every way is therefore resampled at a uniform spacing along its length,
sampled bilinearly and smoothed with a triangular kernel before vertex elevations and
per-segment ascent/descent are derived from it.
"""
from __future__ import annotations

import logging
import os
import re

import numpy as np

log = logging.getLogger(__name__)

TILE_RE = re.compile(r"Copernicus_DSM_COG_\d+_([NS])(\d\d)_00_([EW])(\d\d\d)_00_DEM\.tif$")

SAMPLE_STEP_M = 20.0
SMOOTH_WINDOW_M = 140.0


class DemSampler:
    def __init__(self, directory: str):
        self.tiles: dict[tuple[int, int], str] = {}
        for name in sorted(os.listdir(directory)):
            m = TILE_RE.search(name)
            if not m:
                continue
            lat = int(m.group(2)) * (1 if m.group(1) == "N" else -1)
            lon = int(m.group(4)) * (1 if m.group(3) == "E" else -1)
            self.tiles[(lat, lon)] = os.path.join(directory, name)
        log.info("DEM: %d tiles in %s", len(self.tiles), directory)

    def sample(self, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
        """Bilinear elevation in metres; NaN where no tile covers the point."""
        import rasterio

        lat = np.asarray(lat, dtype=np.float64)
        lon = np.asarray(lon, dtype=np.float64)
        out = np.full(lat.shape, np.nan, dtype=np.float64)
        tlat = np.floor(lat).astype(np.int64)
        tlon = np.floor(lon).astype(np.int64)
        pairs = np.unique(np.stack([tlat, tlon], axis=1), axis=0)
        for la, lo in pairs:
            path = self.tiles.get((int(la), int(lo)))
            if path is None:
                continue
            idx = np.nonzero((tlat == la) & (tlon == lo))[0]
            with rasterio.open(path) as ds:
                data = ds.read(1).astype(np.float32)
                nodata = ds.nodata
                tr = ds.transform
            if nodata is not None:
                data[data == nodata] = np.nan
            cols = (lon[idx] - tr.c) / tr.a - 0.5
            rows = (lat[idx] - tr.f) / tr.e - 0.5
            c0 = np.clip(np.floor(cols).astype(np.int64), 0, data.shape[1] - 2)
            r0 = np.clip(np.floor(rows).astype(np.int64), 0, data.shape[0] - 2)
            fc = np.clip(cols - c0, 0.0, 1.0)
            fr = np.clip(rows - r0, 0.0, 1.0)
            out[idx] = (data[r0, c0] * (1 - fc) * (1 - fr) + data[r0, c0 + 1] * fc * (1 - fr)
                        + data[r0 + 1, c0] * (1 - fc) * fr + data[r0 + 1, c0 + 1] * fc * fr)
            del data
        return out


def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371008.8
    p1 = np.radians(lat1)
    p2 = np.radians(lat2)
    dl = np.radians(np.asarray(lon2) - np.asarray(lon1))
    a = np.sin((p2 - p1) / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(np.minimum(a, 1.0)))


class WayElevation:
    """Smoothed elevation profiles of all ways (uniformly sampled along each way)."""

    def __init__(self, sample_offsets: np.ndarray, sample_dist: np.ndarray, sample_ele: np.ndarray,
                 vertex_dist: np.ndarray, vertex_ele: np.ndarray):
        self.sample_offsets = sample_offsets  # per way: [start, end) into sample arrays
        self.sample_dist = sample_dist        # distance from way start (m)
        self.sample_ele = sample_ele          # smoothed elevation (m), NaN = unknown
        self.vertex_dist = vertex_dist        # aligned with OsmWays.lat
        self.vertex_ele = vertex_ele          # smoothed elevation at vertices

    def ascent_descent(self, way: int, d0: float, d1: float) -> tuple[float, float]:
        """Ascent/descent (m) along way `way` between distances d0 < d1 (forward direction)."""
        s, e = self.sample_offsets[way], self.sample_offsets[way + 1]
        dist = self.sample_dist[s:e]
        ele = self.sample_ele[s:e]
        if e - s < 2 or np.isnan(ele).any():
            return 0.0, 0.0
        i0 = np.searchsorted(dist, d0, side="right")
        i1 = np.searchsorted(dist, d1, side="left")
        xs = np.concatenate([[d0], dist[i0:i1], [d1]])
        ys = np.interp(xs, dist, ele)
        diff = np.diff(ys)
        return float(diff[diff > 0].sum()), float(-diff[diff < 0].sum())


def compute_way_elevation(ways, sampler: DemSampler | None) -> WayElevation:
    n_ways = len(ways)
    lat, lon, off = ways.lat_np, ways.lon_np, ways.offsets_np
    # cumulative distance at vertices, restarting at each way
    seg = np.zeros(len(lat))
    seg[1:] = haversine_m(lat[:-1], lon[:-1], lat[1:], lon[1:])
    seg[off[:-1]] = 0.0
    cum = np.cumsum(seg)
    vertex_dist = cum - np.repeat(cum[off[:-1]], np.diff(off))

    # uniform sample positions per way
    lengths = vertex_dist[off[1:] - 1]
    counts = np.maximum(2, np.ceil(lengths / SAMPLE_STEP_M).astype(np.int64) + 1)
    sample_offsets = np.concatenate([[0], np.cumsum(counts)])
    total = int(sample_offsets[-1])
    sample_dist = np.empty(total)
    s_lat = np.empty(total)
    s_lon = np.empty(total)
    for w in range(n_ways):
        a, b = off[w], off[w + 1]
        s, e = sample_offsets[w], sample_offsets[w + 1]
        d = np.linspace(0.0, lengths[w], e - s)
        vd = vertex_dist[a:b]
        sample_dist[s:e] = d
        s_lat[s:e] = np.interp(d, vd, lat[a:b])
        s_lon[s:e] = np.interp(d, vd, lon[a:b])

    if sampler is None:
        raw = np.full(total, np.nan)
    else:
        raw = sampler.sample(s_lat, s_lon)

    smoothed = np.empty(total)
    vertex_ele = np.empty(len(lat))
    for w in range(n_ways):
        s, e = sample_offsets[w], sample_offsets[w + 1]
        y = raw[s:e]
        a, b = off[w], off[w + 1]
        if np.isnan(y).any():
            smoothed[s:e] = np.nan
            vertex_ele[a:b] = np.nan
            continue
        step = lengths[w] / max(1, (e - s - 1))
        half = max(1, int(round((SMOOTH_WINDOW_M / 2) / max(step, 1.0))))
        half = min(half, (len(y) - 1) // 2)  # np.convolve("same") needs len(kernel) <= len(y)
        kernel = 1.0 - np.abs(np.arange(-half, half + 1)) / (half + 1)
        num = np.convolve(y, kernel, mode="same")
        den = np.convolve(np.ones_like(y), kernel, mode="same")
        ys = num / den
        smoothed[s:e] = ys
        vertex_ele[a:b] = np.interp(vertex_dist[a:b], sample_dist[s:e], ys)

    log.info("Elevation: %d samples for %d ways (%.0f km)", total, n_ways, lengths.sum() / 1000)
    return WayElevation(sample_offsets, sample_dist, smoothed, vertex_dist, vertex_ele)
