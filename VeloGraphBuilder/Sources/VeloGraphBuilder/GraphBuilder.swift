import Foundation

// ─── Output types ────────────────────────────────────────────────────────────

struct BuiltNode {
    let id: Int64
    let lat: Double
    let lon: Double
}

struct BuiltEdge {
    /// Direction-specific: one row for A→B, one separate row for B→A.
    let fromNode: Int64
    let toNode:   Int64
    /// Raw Haversine meters — no quality multiplier baked in.
    /// The iOS CostFunction applies multipliers at query time.
    let distanceM: Double
    /// RoadCondition.rawValue (0–6, lower = better quality)
    let condition: Int32
}

struct BuiltGraph {
    let nodes: [BuiltNode]
    let edges: [BuiltEdge]
}

// ─── Internal keys ───────────────────────────────────────────────────────────

/// Integer grid key for coordinate snapping.
///
/// Quantises coordinates to a 0.0001° grid (~11 m latitude, ~7 m longitude at
/// 50 °N). Two points that round to the same grid centre are treated as the
/// same intersection.  Using integer arithmetic instead of floating-point
/// rounding eliminates the grid-boundary artefact that caused disconnected
/// topology in the previous 8 m metric-grid approach.
private struct SnapKey: Hashable {
    let latKey: Int64   // Int64((lat * 10_000).rounded())
    let lonKey: Int64   // Int64((lon * 10_000).rounded())

    init(lat: Double, lon: Double) {
        latKey = Int64((lat * 10_000.0).rounded())
        lonKey = Int64((lon * 10_000.0).rounded())
    }
}

/// Directed edge key for deduplication.
private struct EdgeKey: Hashable {
    let from: Int64
    let to: Int64
}

// ─── Builder ─────────────────────────────────────────────────────────────────

final class GraphBuilder {

    // Mutable state — reset at the start of each build() call.
    private var nodeMap:    [SnapKey: Int64]  = [:]
    private var nodes:      [BuiltNode]       = []
    private var nextNodeID: Int64             = 0
    /// Directed edge map: EdgeKey → best (lowest-condition) BuiltEdge seen so far.
    private var edgeMap:    [EdgeKey: BuiltEdge] = [:]

    init() {}

    func build(from features: [ParsedFeature]) -> BuiltGraph {
        // Reset in case the builder is reused.
        nodeMap.removeAll(keepingCapacity: true)
        nodes.removeAll(keepingCapacity: true)
        nextNodeID = 0
        edgeMap.removeAll(keepingCapacity: true)

        let totalPolylines = features.reduce(0) { $0 + $1.polylines.count }
        var processedPolylines = 0
        let progressStep = max(1, totalPolylines / 20)   // ~5 % increments

        for feature in features {
            let cond = feature.condition.rawValue
            for polyline in feature.polylines {
                processPolyline(polyline, condition: cond)
                processedPolylines += 1
                if processedPolylines % progressStep == 0 {
                    let pct = Int(Double(processedPolylines) / Double(totalPolylines) * 100)
                    print("      \(pct)%  — nodes: \(nodes.count)  edges: \(edgeMap.count)")
                }
            }
        }

        return BuiltGraph(nodes: nodes, edges: Array(edgeMap.values))
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    private func processPolyline(
        _ polyline: [(lat: Double, lon: Double)],
        condition: Int32
    ) {
        guard polyline.count >= 2 else { return }

        for i in 0 ..< (polyline.count - 1) {
            let p1 = polyline[i]
            let p2 = polyline[i + 1]

            let aID = nodeID(for: p1)
            let bID = nodeID(for: p2)
            guard aID != bID else { continue }   // Same cell after snapping

            let a = nodes[Int(aID)]
            let b = nodes[Int(bID)]
            let dist = Haversine.distanceMeters(
                lat1: a.lat, lon1: a.lon,
                lat2: b.lat, lon2: b.lon
            )
            guard dist > 0.1 else { continue }   // Skip near-zero-length edges

            upsertEdge(from: aID, to: bID, dist: dist, condition: condition)
            upsertEdge(from: bID, to: aID, dist: dist, condition: condition)
        }
    }

    /// Returns the node ID for `point`, creating a new node if this 0.0001°
    /// grid cell has not been seen before.  The first coordinate that maps to
    /// a given cell is stored as the representative position for that node.
    private func nodeID(for point: (lat: Double, lon: Double)) -> Int64 {
        let key = SnapKey(lat: point.lat, lon: point.lon)
        if let id = nodeMap[key] { return id }
        let id = nextNodeID
        nextNodeID += 1
        nodeMap[key] = id
        // Append preserves the invariant: nodes[id] == node with that id.
        nodes.append(BuiltNode(id: id, lat: point.lat, lon: point.lon))
        return id
    }

    /// Inserts or updates a directed edge.
    /// If a directed edge (from→to) already exists, we keep the one with the
    /// better condition (lower rawValue = higher quality road).
    private func upsertEdge(from: Int64, to: Int64, dist: Double, condition: Int32) {
        let key = EdgeKey(from: from, to: to)
        if let existing = edgeMap[key] {
            if condition < existing.condition {
                edgeMap[key] = BuiltEdge(fromNode: from, toNode: to,
                                         distanceM: dist, condition: condition)
            }
        } else {
            edgeMap[key] = BuiltEdge(fromNode: from, toNode: to,
                                     distanceM: dist, condition: condition)
        }
    }
}
