#!/bin/bash
# Downloads the prebuilt road graph (orphan branch `graph-data`) into the app bundle resources.
# Usage: scripts/fetch-graph.sh            (from the repository root)
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=VeloPath/Resources/RoadGraph.vpg
mkdir -p "$(dirname "$DEST")"
git fetch --depth 1 origin graph-data
git show origin/graph-data:RoadGraph.vpg > "$DEST.tmp"
EXPECTED=$(git show origin/graph-data:manifest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')
ACTUAL=$(shasum -a 256 "$DEST.tmp" | cut -d" " -f1)
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "checksum mismatch: $ACTUAL != $EXPECTED" >&2
  rm -f "$DEST.tmp"
  exit 1
fi
mv "$DEST.tmp" "$DEST"
ls -la "$DEST"
