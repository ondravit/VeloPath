"""Read routable ways from an OSM PBF file."""
from __future__ import annotations

import logging
from array import array
from dataclasses import dataclass, field

import numpy as np
import osmium

from .profile import WayProfile, classify_way

log = logging.getLogger(__name__)


@dataclass
class OsmWays:
    """Struct-of-arrays container for all routable ways (memory friendly)."""
    node_ids: array = field(default_factory=lambda: array("q"))
    lat: array = field(default_factory=lambda: array("d"))
    lon: array = field(default_factory=lambda: array("d"))
    offsets: array = field(default_factory=lambda: array("q", [0]))
    way_ids: array = field(default_factory=lambda: array("q"))
    profiles: list[WayProfile] = field(default_factory=list)

    def __len__(self) -> int:
        return len(self.profiles)

    def way_slice(self, i: int) -> slice:
        return slice(self.offsets[i], self.offsets[i + 1])

    def finalize(self) -> None:
        self.node_ids_np = np.frombuffer(self.node_ids, dtype=np.int64)
        self.lat_np = np.frombuffer(self.lat, dtype=np.float64)
        self.lon_np = np.frombuffer(self.lon, dtype=np.float64)
        self.offsets_np = np.frombuffer(self.offsets, dtype=np.int64)


def read_ways(pbf_path: str, bbox: tuple[float, float, float, float] | None = None) -> OsmWays:
    """Collect all ways usable by the road-bike profile.

    bbox = (min_lon, min_lat, max_lon, max_lat) optionally restricts the result to ways
    with at least one node inside the box.
    """
    out = OsmWays()
    profile_cache: dict[tuple, WayProfile] = {}
    skipped_locations = 0
    total = 0

    fp = (osmium.FileProcessor(pbf_path, osmium.osm.WAY | osmium.osm.NODE)
          .with_locations(osmium.index.create_map("flex_mem"))
          .with_filter(osmium.filter.EntityFilter(osmium.osm.WAY))
          .with_filter(osmium.filter.KeyFilter("highway")))

    for w in fp:
        total += 1
        tags = {t.k: t.v for t in w.tags}
        prof = classify_way(tags)
        if prof is None:
            continue
        nodes = w.nodes
        if len(nodes) < 2:
            continue
        try:
            coords = [(n.ref, n.lat, n.lon) for n in nodes]
        except osmium.InvalidLocationError:
            skipped_locations += 1
            continue
        if bbox is not None:
            min_lon, min_lat, max_lon, max_lat = bbox
            if not any(min_lat <= la <= max_lat and min_lon <= lo <= max_lon for _, la, lo in coords):
                continue
        # drop consecutive duplicate node refs (broken ways)
        dedup = [coords[0]]
        for c in coords[1:]:
            if c[0] != dedup[-1][0]:
                dedup.append(c)
        if len(dedup) < 2:
            continue
        key = (prof.road_class, prof.surface, prof.oneway, prof.condition, prof.dismount, prof.ref, prof.name)
        prof = profile_cache.setdefault(key, prof)
        for ref, la, lo in dedup:
            out.node_ids.append(ref)
            out.lat.append(la)
            out.lon.append(lo)
        out.offsets.append(len(out.node_ids))
        out.way_ids.append(w.id)
        out.profiles.append(prof)

    out.finalize()
    log.info("OSM: %d highway ways scanned, %d routable, %d node refs, %d skipped (missing locations)",
             total, len(out), len(out.node_ids), skipped_locations)
    return out
