"""Generate routing fixtures for the Swift unit tests.

    python -m velopath_pipeline.fixtures GRAPH.vpg OUT.json

Picks deterministic pseudo-random origin/destination pairs, snaps and routes them with the
reference implementation and stores the expected snap positions, costs and distances.
"""
from __future__ import annotations

import json
import random
import sys

from . import reference as R

OPTIONS = [("direct", False, 0.0), ("balanced", False, 0.5), ("best", True, 1.0)]


def main(argv=None) -> None:
    argv = argv or sys.argv[1:]
    graph_path, out_path = argv[0], argv[1]
    gf = R.GraphFile.load(graph_path)
    lat = gf.arrays["node_lat"] / 1e7
    lon = gf.arrays["node_lon"] / 1e7
    rng = random.Random(20261118)
    cases = []
    tries = 0
    while len(cases) < 24 and tries < 500:
        tries += 1
        i, j = rng.randrange(gf.n), rng.randrange(gf.n)
        # offset the query from the node so that snapping is exercised
        q1 = (float(lat[i]) + rng.uniform(-0.0012, 0.0012), float(lon[i]) + rng.uniform(-0.0012, 0.0012))
        q2 = (float(lat[j]) + rng.uniform(-0.0012, 0.0012), float(lon[j]) + rng.uniform(-0.0012, 0.0012))
        s, d = R.snap(gf, *q1), R.snap(gf, *q2)
        if s is None or d is None:
            continue
        name, avoid, q = OPTIONS[len(cases) % len(OPTIONS)]
        cost, legs, _ = R.route(gf, s, d, R.cost_table(q, avoid))
        case = {
            "from": list(q1), "to": list(q2),
            "priority": name, "avoidMainRoads": avoid,
            "snapFrom": {"geometry": s.geom, "offset": s.along, "distance": s.dist},
            "snapTo": {"geometry": d.geom, "offset": d.along, "distance": d.dist},
        }
        if cost is None:
            case["noRoute"] = True
        else:
            case["cost"] = cost
            case["distance"] = sum(abs(l[3] - l[2]) for l in legs)
            case["geometries"] = [int(l[0]) for l in legs]
        cases.append(case)
    with open(out_path, "w") as f:
        json.dump({"graph": graph_path.split("/")[-1], "cases": cases}, f, indent=1)
    print(f"{len(cases)} cases written to {out_path}")


if __name__ == "__main__":
    main()
