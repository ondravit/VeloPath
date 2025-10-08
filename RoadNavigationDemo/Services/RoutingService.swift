//
//  RoutingService.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import CoreLocation

final class RoutingService {

    private let graph: RoadGraph

    init(roadSegments: [RoadSegment]) {
        self.graph = RoadGraph(roadSegments: roadSegments)
    }

    /// Async A* route between coordinates. Runs off the main thread.
    func route(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D] {
        guard let s = graph.nearestNode(to: start),
              let g = graph.nearestNode(to: end) else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let nodes = AStar.findPath(in: self.graph, from: s, to: g)
                let coords = nodes.map { $0.coordinate }
                continuation.resume(returning: coords)
            }
        }
    }
}
