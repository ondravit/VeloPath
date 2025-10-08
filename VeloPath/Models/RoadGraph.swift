//
//  RoadGraph.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import CoreLocation

final class RoadGraph {
    /// Adjacency list
    private(set) var edges: [GraphNode: [GraphEdge]] = [:]
    /// For nearest-node lookup
    private(set) var nodes: [GraphNode] = []

    init(roadSegments: [RoadSegment],
         mergeToleranceMeters: Double = 8,            // merges close endpoints
         conditionMultiplier: (RoadSegment.RoadCondition) -> Double = RoadGraph.defaultMultiplier) {

        // 1) Create canonical nodes with snapping (merging nearby endpoints)
        var canonical: [CoordinateKey: GraphNode] = [:]

        func node(for coord: CLLocationCoordinate2D) -> GraphNode {
            let snapped = coord.snapped(toMeters: mergeToleranceMeters)
            let key = CoordinateKey(coordinate: snapped)
            if let n = canonical[key] { return n }
            let n = GraphNode(coordinate: snapped)
            canonical[key] = n
            return n
        }


        // 2) Build edges between consecutive points in each road polyline
        for seg in roadSegments {
            guard seg.coordinates.count >= 2 else { continue }
            let mult = conditionMultiplier(seg.condition)
            let coords = seg.coordinates

            for i in 0..<(coords.count - 1) {
                let a = node(for: coords[i])
                let b = node(for: coords[i + 1])
                let distance = a.coordinate.distance(to: b.coordinate) // meters
                guard distance > 0 else { continue }

                let cost = distance * mult

                let e1 = GraphEdge(from: a, to: b, cost: cost)
                let e2 = GraphEdge(from: b, to: a, cost: cost)

                edges[a, default: []].append(e1)
                edges[b, default: []].append(e2)
            }
        }

        nodes = Array(edges.keys)
    }

    nonisolated static func defaultMultiplier(_ c: RoadSegment.RoadCondition) -> Double {
        switch c {
        case .excellent:       return 1.00
        case .good:            return 1.10
        case .satisfactory:    return 1.20
        case .unsatisfactory:  return 1.45
        case .emergency:       return 1.90
        case .superemergency:  return 2.50
        case .unknown:         return 1.35
        }
    }

    /// Brute nearest; for large graphs replace with a spatial index later.
    func nearestNode(to coord: CLLocationCoordinate2D) -> GraphNode? {
        guard !nodes.isEmpty else { return nil }
        var best: GraphNode = nodes[0]
        var bestD = coord.distance(to: best.coordinate)
        for n in nodes.dropFirst() {
            let d = coord.distance(to: n.coordinate)
            if d < bestD { bestD = d; best = n }
        }
        return best
    }

    func neighbors(of node: GraphNode) -> [GraphEdge] {
        edges[node] ?? []
    }
}
