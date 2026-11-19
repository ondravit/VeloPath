"""Reduce a large OSM extract to highway ways and the nodes they reference.

    python -m velopath_pipeline.prefilter czech-republic-YYMMDD.osm.pbf cz-highways-YYMMDD.osm.pbf

The Czech extract (~950 MB) shrinks to ~150 MB, which the graph builder processes with
far less memory. Takes about two minutes.
"""
from __future__ import annotations

import sys
import time

import osmium

from .profile import ROAD_CLASSES


def main(argv=None) -> None:
    src, dst = (argv or sys.argv[1:])[:2]
    t0 = time.time()
    count = 0
    # BackReferenceWriter adds every node referenced by the written ways in a second pass.
    with osmium.BackReferenceWriter(dst, ref_src=src, overwrite=True) as writer:
        for w in osmium.FileProcessor(src, osmium.osm.WAY).with_filter(osmium.filter.KeyFilter("highway")):
            if w.tags.get("highway") in ROAD_CLASSES:
                writer.add_way(w)
                count += 1
    print(f"{count} ways (+ referenced nodes) written to {dst} in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()
