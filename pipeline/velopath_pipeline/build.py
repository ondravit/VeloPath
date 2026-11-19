"""Command line entry point: build a VeloPath road graph.

    python -m velopath_pipeline.build \
        --osm data/raw/kralovehradecky-261117.osm.pbf \
        --dem data/raw \
        --condition-khk data/raw/khk_stav_povrchu_silnic.geojson \
        --region "Královéhradecký kraj" \
        --out VeloPath/Resources/RoadGraph.vpg
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import logging
import os
import re
import time

import numpy as np

from .condition import load_khk_layer
from .elevation import DemSampler, compute_way_elevation
from .graph import build_pieces, contract, finalize, largest_component_filter, simplify
from .model import RoadClass, ConditionSource, unpack_attr
from .osm_reader import read_ways
from .writer import write_graph

log = logging.getLogger("velopath")


def _osm_date(path: str) -> str | None:
    m = re.search(r"-(\d{6})\.osm\.pbf$", os.path.basename(path))
    if m:
        s = m.group(1)
        return f"20{s[0:2]}-{s[2:4]}-{s[4:6]}"
    return None


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--osm", required=True, help="OSM .pbf extract")
    ap.add_argument("--dem", help="directory with Copernicus GLO-30 tiles")
    ap.add_argument("--condition-khk", help="Data KHK 'Stav povrchu silnic' GeoJSON (EPSG:4326)")
    ap.add_argument("--region", default="Česká republika")
    ap.add_argument("--bbox", help="min_lon,min_lat,max_lon,max_lat")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    t0 = time.time()
    bbox = tuple(float(v) for v in args.bbox.split(",")) if args.bbox else None
    ways = read_ways(args.osm, bbox)
    sampler = DemSampler(args.dem) if args.dem else None
    elevation = compute_way_elevation(ways, sampler)
    official = load_khk_layer(args.condition_khk) if args.condition_khk else None
    pieces = build_pieces(ways, elevation, official)
    geoms = contract(pieces)
    simplify(geoms)
    graph = largest_component_filter(finalize(geoms))

    # statistics for the metadata block / README
    km_by_class = collections.Counter()
    km_by_source = collections.Counter()
    for p in graph.geoms:
        rc, _surf, _cond, src, _dis = unpack_attr(p.attr)
        km_by_class[RoadClass(rc).name.lower()] += p.length / 1000
        km_by_source[ConditionSource(src).name.lower()] += p.length / 1000

    sources = [{
        "name": "OpenStreetMap",
        "attribution": "© přispěvatelé OpenStreetMap",
        "license": "ODbL 1.0",
        "url": "https://www.openstreetmap.org/copyright",
        "date": _osm_date(args.osm),
    }]
    if official is not None:
        years = sorted({int(y) for y in official.year if y})
        sources.append({
            "name": "Stav povrchu silnic – Královéhradecký kraj",
            "attribution": "Královéhradecký kraj, ÚDRŽBA SILNIC Královéhradeckého kraje a.s. (Data KHK)",
            "license": "Otevřená data",
            "url": "https://www.datakhk.cz/datasets/311df195461541069a5690e9491eb092_0",
            "years": [years[0], years[-1]] if years else None,
        })
    if sampler is not None and sampler.tiles:
        sources.append({
            "name": "Copernicus DEM GLO-30",
            "attribution": "© DLR e.V. 2010–2014 a © Airbus Defence and Space GmbH 2014–2018, poskytnuto v rámci programu COPERNICUS Evropskou unií a ESA",
            "license": "Copernicus DEM licence",
            "url": "https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model",
        })
    metadata = {
        "format": "VPGRAPH1",
        "region": args.region,
        "built": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "profile": "road-bike-v1",
        "sources": sources,
        "stats": {
            "km_by_class": {k: round(v, 1) for k, v in sorted(km_by_class.items())},
            "km_by_condition_source": {k: round(v, 1) for k, v in sorted(km_by_source.items())},
        },
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    info = write_graph(args.out, graph, metadata)
    log.info("Done in %.0f s: %s", time.time() - t0, info)
    log.info("km by condition source: %s", metadata["stats"]["km_by_condition_source"])


if __name__ == "__main__":
    main()
