"""Road-bike interpretation of OpenStreetMap way tags.

`classify_way` decides whether a way belongs to the road-cycling network and, if so,
returns the attributes the router needs.  The rules follow Czech traffic law and the
Czech OSM tagging conventions (https://wiki.openstreetmap.org/wiki/Cs:Czech_tagging_guidelines):

* motorways, motorroads (`motorroad=yes`) and trunk roads are closed to bicycles;
* footways and paths are only usable when bicycles are explicitly allowed;
* unpaved surfaces are excluded – this is a road-bike planner.  Compacted / fine gravel
  is kept on dedicated cycle paths only, with a heavy routing penalty, so that the
  network stays connected along river-side cycle paths.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Optional

from .model import Condition, RoadClass, Surface

PAVED_SURFACES = {
    "asphalt": Surface.ASPHALT,
    "paved": Surface.ASPHALT,
    "concrete": Surface.ASPHALT,
    "chipseal": Surface.ASPHALT,
    "concrete:lanes": Surface.CONCRETE_PLATES,
    "concrete:plates": Surface.CONCRETE_PLATES,
    "paving_stones": Surface.PAVING_STONES,
    "paving_stones:lanes": Surface.PAVING_STONES,
    "bricks": Surface.PAVING_STONES,
    "sett": Surface.SETT,
    "unhewn_cobblestone": Surface.COBBLESTONE,
    "cobblestone": Surface.COBBLESTONE,
    "stone": Surface.COBBLESTONE,
    "wood": Surface.OTHER_PAVED,
    "metal": Surface.OTHER_PAVED,
    "metal_grid": Surface.OTHER_PAVED,
    "rubber": Surface.OTHER_PAVED,
    "tartan": Surface.OTHER_PAVED,
}
LIGHT_GRAVEL = {"compacted", "fine_gravel"}

# smoothness -> pavement condition; None = impassable for a road bike
SMOOTHNESS = {
    "excellent": Condition.EXCELLENT,
    "good": Condition.GOOD,
    "intermediate": Condition.SATISFACTORY,
    "bad": Condition.UNSATISFACTORY,
    "very_bad": Condition.EMERGENCY,
}
SMOOTHNESS_EXCLUDED = {"horrible", "very_horrible", "impassable", "high_clearance",
                       "off_road_wheels", "specialized_off_road_wheels"}

BIKE_YES = {"yes", "designated", "permissive", "official"}
ACCESS_NO = {"no", "private", "agricultural", "forestry", "military", "delivery", "emergency", "permit"}

ROAD_CLASSES = {
    "primary": RoadClass.PRIMARY, "primary_link": RoadClass.PRIMARY,
    "secondary": RoadClass.SECONDARY, "secondary_link": RoadClass.SECONDARY,
    "tertiary": RoadClass.TERTIARY, "tertiary_link": RoadClass.TERTIARY,
    "unclassified": RoadClass.UNCLASSIFIED, "road": RoadClass.UNCLASSIFIED,
    "residential": RoadClass.RESIDENTIAL,
    "living_street": RoadClass.LIVING_STREET,
    "service": RoadClass.SERVICE,
    "cycleway": RoadClass.CYCLEWAY,
    "track": RoadClass.TRACK,
    "pedestrian": RoadClass.LIVING_STREET,
    "footway": RoadClass.SHARED_PATH, "path": RoadClass.SHARED_PATH,
    "bridleway": RoadClass.SHARED_PATH,
    "trunk": RoadClass.TRUNK, "trunk_link": RoadClass.TRUNK,
}
# Ways of these classes need an explicit bicycle permission.
NEEDS_BIKE_PERMISSION = {"pedestrian", "footway", "path", "bridleway", "trunk", "trunk_link"}

# Parking aisles and driveways only bloat the graph; waypoints there snap to the street.
SERVICE_EXCLUDED = {"parking_aisle", "driveway", "drive-through", "emergency_access"}

OPPOSITE_CYCLEWAY = {"opposite", "opposite_lane", "opposite_track", "opposite_share_busway"}


@dataclass(frozen=True)
class WayProfile:
    road_class: RoadClass
    surface: Surface
    oneway: int               # 0 = both directions, 1 = forward only, -1 = backward only
    condition: Condition      # from OSM smoothness, UNKNOWN when not tagged
    dismount: bool
    ref: Optional[str]        # road number, e.g. "611" or "3167"
    name: Optional[str]


def _tag(tags: Mapping[str, str], key: str) -> Optional[str]:
    v = tags.get(key)
    return v.strip().lower() if v else None


def _oneway(tags: Mapping[str, str], highway: str) -> int:
    ow = _tag(tags, "oneway")
    bike = _tag(tags, "oneway:bicycle")
    if bike == "no":
        return 0
    for key in ("cycleway", "cycleway:left", "cycleway:right", "cycleway:both"):
        if _tag(tags, key) in OPPOSITE_CYCLEWAY:
            return 0
    for key in ("cycleway:left:oneway", "cycleway:right:oneway"):
        if _tag(tags, key) == "-1":
            return 0
    if bike in ("yes", "1", "true"):
        return 1
    if bike == "-1":
        return -1
    if ow in ("yes", "1", "true"):
        return 1
    if ow in ("-1", "reverse"):
        return -1
    if ow == "no":
        return 0
    junction = _tag(tags, "junction")
    if junction in ("roundabout", "circular"):
        return 1
    return 0


def classify_way(tags: Mapping[str, str]) -> Optional[WayProfile]:
    highway = _tag(tags, "highway")
    if highway is None or highway not in ROAD_CLASSES:
        return None
    if _tag(tags, "area") == "yes":
        return None
    if _tag(tags, "motorroad") == "yes":
        return None
    bicycle = _tag(tags, "bicycle")
    if bicycle in ("no", "use_sidepath", "private"):
        return None
    bike_allowed = bicycle in BIKE_YES or highway == "cycleway"

    if highway in NEEDS_BIKE_PERMISSION and not bike_allowed:
        return None
    access = _tag(tags, "access")
    vehicle = _tag(tags, "vehicle")
    if (access in ACCESS_NO or vehicle in ("no", "private")) and not bike_allowed:
        return None

    road_class = ROAD_CLASSES[highway]
    if highway == "service" and _tag(tags, "service") in SERVICE_EXCLUDED:
        return None

    # --- surface -------------------------------------------------------------------
    raw_surface = _tag(tags, "surface")
    if raw_surface:
        raw_surface = raw_surface.split(";")[0]
    if raw_surface in PAVED_SURFACES:
        surface = PAVED_SURFACES[raw_surface]
    elif raw_surface in LIGHT_GRAVEL:
        # keep light gravel only on paths explicitly built for bicycles
        if road_class == RoadClass.CYCLEWAY or (road_class == RoadClass.SHARED_PATH and bicycle == "designated"):
            surface = Surface.FINE_GRAVEL
        else:
            return None
    elif raw_surface is None:
        if road_class == RoadClass.TRACK:
            if _tag(tags, "tracktype") != "grade1":
                return None
        elif road_class == RoadClass.SHARED_PATH:
            return None  # untagged paths are mostly dirt
        surface = Surface.UNKNOWN
    else:
        return None  # unpaved

    if road_class == RoadClass.TRACK and _tag(tags, "tracktype") not in (None, "grade1"):
        # surface says paved but tracktype says otherwise -> trust surface only for asphalt/concrete
        if surface not in (Surface.ASPHALT, Surface.CONCRETE_PLATES):
            return None

    # --- smoothness ----------------------------------------------------------------
    smoothness = _tag(tags, "smoothness")
    if smoothness in SMOOTHNESS_EXCLUDED:
        return None
    condition = SMOOTHNESS.get(smoothness, Condition.UNKNOWN) if smoothness else Condition.UNKNOWN

    ref = tags.get("ref")
    return WayProfile(
        road_class=road_class,
        surface=surface,
        oneway=_oneway(tags, highway),
        condition=condition,
        dismount=bicycle == "dismount",
        ref=ref.strip() if ref else None,
        name=tags.get("name"),
    )


def normalize_ref(ref: Optional[str]) -> set[str]:
    """'II/611', '0611', '611;303' -> {'611', '303'}"""
    if not ref:
        return set()
    out = set()
    for part in ref.replace(",", ";").split(";"):
        part = part.strip().upper()
        for prefix in ("III/", "II/", "I/"):
            if part.startswith(prefix):
                part = part[len(prefix):]
        part = part.lstrip("0")
        if part:
            out.add(part)
    return out
