# VeloPath

Plan road-bike routes in the Czech Republic that stay on the best pavement, then export them as GPX
to Garmin, Wahoo, Hammerhead, Strava, Komoot or any other device.

* **Routing on the phone, offline.** The whole Czech road network (≈ 164 000 km usable by a
  road bike) ships with the app as a 98 MB memory-mapped graph; routes are computed in
  milliseconds by an A* router written in Swift.
* **Pavement condition.** The official survey of class II and III roads
  ("Stav povrchu silnic", Královéhradecký kraj, TP 87 classification) is matched onto
  OpenStreetMap roads. Elsewhere the OSM `smoothness` and `surface` tags are used.
  Three routing preferences: *Přímá*, *Vyvážená*, *Nejlepší povrch*, plus *avoid class I roads*.
* **Road-bike profile.** No motorways / motorroads, no unpaved roads, footpaths only where bikes
  are allowed, one-way streets respected (with contraflow exceptions), cobbles and sett penalised.
* **Elevation.** Copernicus GLO-30 DEM: ascent, descent, elevation profile, elevations in GPX.

## Repository layout

| path | what |
|---|---|
| `VeloPath/` | SwiftUI + MapKit iOS app (iOS 18+, Liquid Glass on iOS 26) |
| `VeloCore/` | Swift package: graph loader, router, snapping, route statistics, GPX writer + tests |
| `pipeline/` | Python pipeline that builds the road graph from OSM, the condition layer and the DEM |
| `docs/graph-format.md` | binary graph format (`VPGRAPH1`) |
| `scripts/` | CI helpers and `fetch-graph.sh` |
| branch `graph-data` | the prebuilt `RoadGraph.vpg` (single force-pushed commit, keeps history small) |
| branch `ci-reports` | logs and simulator screenshots of the latest CI run |

## Building without a local Xcode

Every push to `main` / `rebuild-v2` runs `.github/workflows/ci.yml` on a GitHub-hosted Mac:

1. downloads the road graph (`scripts/fetch-graph.sh`),
2. runs the `VeloCore` unit tests (they compare every route with the Python reference router),
3. builds the app for the simulator and captures screenshots (`ci-reports` branch, `latest/`),
4. builds an **unsigned IPA** and publishes it as the GitHub pre-release
   [`build-latest`](../../releases/tag/build-latest).

### Installing on an iPhone (free Apple ID)

1. Download `VeloPath-*.ipa` from the `build-latest` release.
2. Install [Sideloadly](https://sideloadly.io) on the Mac, connect the iPhone with a cable.
3. Drag the IPA into Sideloadly, enter your Apple ID, press *Start*.
4. On the iPhone: *Settings → General → VPN & Device Management* → trust your developer
   profile; on iOS 16+ also enable *Settings → Privacy & Security → Developer Mode*.

Apps signed with a free Apple ID expire after 7 days – just repeat step 3.
With a paid Apple Developer account the workflow can be extended to upload to TestFlight.

### Building locally (optional)

```bash
scripts/fetch-graph.sh          # puts RoadGraph.vpg into VeloPath/Resources
open VeloPath.xcodeproj         # Xcode 26+
cd VeloCore && swift test       # core tests without Xcode UI
```

## Rebuilding the road graph

```bash
cd pipeline
pip install -r requirements.txt
# inputs (data/raw is git-ignored):
#   Geofabrik extract   https://download.geofabrik.de/europe/czech-republic.html
#   KHK condition layer https://www.datakhk.cz/datasets/311df195461541069a5690e9491eb092_0
#   Copernicus GLO-30   https://copernicus-dem-30m.s3.amazonaws.com/  (1° tiles N48–N51, E012–E018)
python -m velopath_pipeline.build \
    --osm ../data/raw/czech-republic-YYMMDD.osm.pbf \
    --dem ../data/raw \
    --condition-khk ../data/raw/khk_stav_povrchu_silnic.geojson \
    --region "Česká republika" \
    --out ../data/build/RoadGraph.vpg
```

The full Czech extract needs ~5 GB RAM. Pre-filtering it to highways first makes the build much
lighter: `python -m velopath_pipeline.prefilter czech-republic-YYMMDD.osm.pbf cz-highways-YYMMDD.osm.pbf`.
After a rebuild, regenerate the test fixtures if the format or cost model changed:

```bash
python -m velopath_pipeline.build --osm ... --bbox 15.78,50.16,15.98,50.30 \
    --out ../VeloCore/Tests/VeloCoreTests/Fixtures/hradec.vpg
python -m velopath_pipeline.fixtures ../VeloCore/Tests/VeloCoreTests/Fixtures/hradec.vpg \
    ../VeloCore/Tests/VeloCoreTests/Fixtures/expected_routes.json
```

The cost model lives in two places that must stay identical:
`VeloCore/Sources/VeloCore/Routing/CostModel.swift` and `pipeline/velopath_pipeline/reference.py`
(the tests fail if they diverge).

## Data sources and licences

* Road network © OpenStreetMap contributors, [ODbL 1.0](https://www.openstreetmap.org/copyright).
* Pavement condition: Královéhradecký kraj / ÚDRŽBA SILNIC Královéhradeckého kraje a.s., open data (Data KHK, NKOD).
* Elevation: Copernicus DEM GLO-30 © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018,
  provided under COPERNICUS by the European Union and ESA.
* Base map: Apple Maps (MapKit).

The attribution is shown in the app (*Nastavení → Mapová data*).

## Roadmap

* Pavement condition outside Královéhradecký kraj: request the TP 87 survey data from the other
  regional road administrations, and add crowdsourced ratings (stored as `ConditionSource.community`).
* Saved routes library, GPX import, turn-by-turn cues in the GPX.
* Optional climbing-aware routing (avoid steep climbs).
