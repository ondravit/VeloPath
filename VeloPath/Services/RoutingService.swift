//
//  RoutingService.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import CoreLocation

final class RoutingService {

    private let baseGraph: RoadGraph
    private let allSegments: [RoadSegment]     // ⬅️ přidej

    init(roadSegments: [RoadSegment]) {
        self.allSegments = roadSegments        // ⬅️ ulož
        self.baseGraph = RoadGraph(roadSegments: roadSegments)
    }

    /// Async A* route between coordinates. Runs off the main thread.
    // RoutingService.swift
    func route(from start: CLLocationCoordinate2D,
               to end: CLLocationCoordinate2D,
               quality: Double) async -> [CLLocationCoordinate2D] {

        // hranice slideru pro jistotu
        let q = max(0, min(1, quality))

        // graf s míchaným multiplikátorem
        let blended = RoadGraph(
            roadSegments: self.baseGraph.nodes.isEmpty ? [] : [], // nebude použito
            conditionMultiplier: { _ in 1.0 } // placeholder
        )
        // ⚠️ výše jen obejití signatury; reálný graf vytvoříme níže znova…

        // ⚙️ postavíme graf od nuly s naším callbackem
        let graph = RoadGraph(
            roadSegments: allSegments, // viz níže – přidáme uložení všech segmentů
            conditionMultiplier: { cond in
                let base = 1.0
                let penal = RoadGraph.defaultMultiplier(cond)
                let strength = 5.0        // 👈 zvýší citlivost slideru
                let mix = (1 - q) * base + q * (base + (penal - base) * strength)
                return mix
            }
        )

        guard let s = graph.nearestNode(to: start),
              let g = graph.nearestNode(to: end) else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let nodes = AStar.findPath(in: graph, from: s, to: g)
                continuation.resume(returning: nodes.map { $0.coordinate })
            }
        }
    }

}
