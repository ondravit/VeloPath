# VPGRAPH1 – binary road graph format

One little-endian file, memory-mapped by the app (`VeloCore/RoadGraph`). Written by
`pipeline/velopath_pipeline/writer.py`, read by `RoadGraph.swift` and `reference.py`.

## Header (512 bytes)

| offset | type | field |
|---|---|---|
| 0 | char[8] | magic `VPGRAPH1` |
| 8 | u32 | format version (1) |
| 12 | u32 | header size (512) |
| 16 | u32 ×7 | node count, directed edge count, geometry count, coordinate count, grid rows, grid cols, grid item count |
| 44 | i32 ×4 | bounding box min lat, min lon, max lat, max lon (degrees × 10⁷) |
| 60 | i32 ×4 | grid origin lat, origin lon, cell height, cell width (degrees × 10⁷) |
| 76 | u32 | section count (19) |
| 80 | {u64 offset, u64 length} × N | section table |

## Sections (each 8-byte aligned)

| # | name | type | count | meaning |
|---|---|---|---|---|
| 0 | node_lat | i32 | N | node latitude × 10⁷ |
| 1 | node_lon | i32 | N | node longitude × 10⁷ |
| 2 | first_edge | u32 | N+1 | CSR: outgoing edges of node *i* are `first_edge[i] ..< first_edge[i+1]` |
| 3 | edge_target | u32 | E | target node |
| 4 | edge_geom | u32 | E | geometry id; bit 31 set = geometry travelled backwards |
| 5 | geom_length | f32 | G | metres |
| 6 | geom_attr | u16 | G | bits 0–3 road class, 4–6 surface, 7–9 condition, 10–11 condition source, 12 dismount |
| 7 | geom_year | u8 | G | survey year − 2000 of the official condition (0 = none) |
| 8 | geom_ascent | u16 | G | decimetres, in stored direction |
| 9 | geom_descent | u16 | G | decimetres, in stored direction |
| 10 | geom_first_coord | u32 | G+1 | coordinate range of each geometry |
| 11 | coord_lat | i32 | C | × 10⁷ |
| 12 | coord_lon | i32 | C | × 10⁷ |
| 13 | coord_ele | i16 | C | decimetres, −32768 = unknown |
| 14 | grid_cell_start | u32 | rows·cols+1 | spatial index (row-major cells) |
| 15 | grid_items | u32 | items | geometry ids touching each cell |
| 16 | metadata | u8 | – | UTF-8 JSON: region, build time, data sources & attribution, statistics |
| 17 | geom_node_u | u32 | G | start node of geometry |
| 18 | geom_node_v | u32 | G | end node of geometry |

Enumerations (road class, surface, condition, source) are defined in
`pipeline/velopath_pipeline/model.py` and mirrored in
`VeloCore/Sources/VeloCore/Model/RoadAttributes.swift`. Values are never renumbered.

Every geometry is a stretch of road between two junctions with uniform attributes;
degree-2 nodes are contracted away, so the graph only contains real junctions.
