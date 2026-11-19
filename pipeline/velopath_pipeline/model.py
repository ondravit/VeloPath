"""Shared enumerations of the VeloPath road graph.

These numeric codes are part of the binary graph format (see docs/graph-format.md)
and are mirrored 1:1 in the Swift package (VeloCore/Sources/VeloCore/Model/RoadAttributes.swift).
Never renumber an existing value; only append.
"""
from __future__ import annotations

from enum import IntEnum


class RoadClass(IntEnum):
    CYCLEWAY = 0        # dedicated cycleway (cyklostezka)
    SHARED_PATH = 1     # path / footway / bridleway where bicycles are allowed
    TRACK = 2           # paved agricultural / forest road
    LIVING_STREET = 3   # living street, pedestrian zone with bicycle access
    SERVICE = 4
    RESIDENTIAL = 5
    UNCLASSIFIED = 6
    TERTIARY = 7        # silnice III. třídy (usually)
    SECONDARY = 8       # silnice II. třídy
    PRIMARY = 9         # silnice I. třídy
    TRUNK = 10          # only when bicycles are explicitly allowed


class Surface(IntEnum):
    ASPHALT = 0         # asphalt, concrete, chipseal, generic "paved"
    CONCRETE_PLATES = 1 # concrete plates / lanes (joints)
    PAVING_STONES = 2   # zámková dlažba
    SETT = 3            # žulové kostky
    COBBLESTONE = 4     # cobblestone, unhewn cobblestone, stone
    UNKNOWN = 5         # no surface tag, assumed paved
    FINE_GRAVEL = 6     # compacted / fine gravel (only on cycle paths)
    OTHER_PAVED = 7     # wood, metal (bridges)


class Condition(IntEnum):
    """Pavement condition, TP 87 classification used by Czech road administrations."""
    EXCELLENT = 0       # výborný
    GOOD = 1            # dobrý
    SATISFACTORY = 2    # vyhovující
    UNSATISFACTORY = 3  # nevyhovující
    EMERGENCY = 4       # havarijní
    SUPER_EMERGENCY = 5 # superhavarijní
    UNKNOWN = 7


class ConditionSource(IntEnum):
    NONE = 0
    OFFICIAL = 1        # road administration survey (e.g. Data KHK "Stav povrchu silnic")
    OSM_SMOOTHNESS = 2  # derived from the OSM smoothness tag
    COMMUNITY = 3       # reserved for crowdsourced ratings


# Bit layout of the 16-bit per-geometry attribute word.
CLASS_SHIFT, CLASS_MASK = 0, 0xF
SURFACE_SHIFT, SURFACE_MASK = 4, 0x7
CONDITION_SHIFT, CONDITION_MASK = 7, 0x7
SOURCE_SHIFT, SOURCE_MASK = 10, 0x3
DISMOUNT_BIT = 1 << 12


def pack_attr(road_class: int, surface: int, condition: int, source: int, dismount: bool) -> int:
    return (
        (road_class & CLASS_MASK) << CLASS_SHIFT
        | (surface & SURFACE_MASK) << SURFACE_SHIFT
        | (condition & CONDITION_MASK) << CONDITION_SHIFT
        | (source & SOURCE_MASK) << SOURCE_SHIFT
        | (DISMOUNT_BIT if dismount else 0)
    )


def unpack_attr(attr: int) -> tuple[int, int, int, int, bool]:
    return (
        (attr >> CLASS_SHIFT) & CLASS_MASK,
        (attr >> SURFACE_SHIFT) & SURFACE_MASK,
        (attr >> CONDITION_SHIFT) & CONDITION_MASK,
        (attr >> SOURCE_SHIFT) & SOURCE_MASK,
        bool(attr & DISMOUNT_BIT),
    )
