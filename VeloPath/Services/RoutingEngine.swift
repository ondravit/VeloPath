import Foundation
import VeloCore

/// Polylines of one pavement condition inside one map chunk (used for the map overlay).
struct ConditionChunk: Sendable, Identifiable {
    let id: String
    let condition: RoadCondition
    let polylines: [[GeoCoordinate]]
}

/// Owns the road graph and the router. All routing work runs off the main thread,
/// serialised by the actor (the router's search buffers are not thread-safe).
actor RoutingEngine {
    nonisolated let graph: RoadGraph
    private let router: Router
    private var legCache: [LegKey: RouteLeg] = [:]
    private var cacheOrder: [LegKey] = []
    private let cacheLimit = 64

    private struct LegKey: Hashable {
        let from: NetworkPoint
        let to: NetworkPoint
        let options: RoutingOptions
    }

    init(graph: RoadGraph) {
        self.graph = graph
        router = Router(graph: graph)
    }

    static func loadBundledGraph() throws -> RoadGraph {
        guard let url = Bundle.main.url(forResource: "RoadGraph", withExtension: "vpg") else {
            throw RoadGraphError.cannotOpen("RoadGraph.vpg")
        }
        return try RoadGraph(contentsOf: url)
    }

    /// Snaps a coordinate to the nearest road usable by a road bike.
    func snap(_ coordinate: GeoCoordinate, maxDistance: Double = 400) -> NetworkPoint? {
        router.snap(coordinate, maxDistance: maxDistance)
    }

    /// Computes a route through the given points. Legs are cached, so moving one waypoint
    /// only recomputes the two legs that touch it.
    func route(through points: [NetworkPoint], options: RoutingOptions) throws -> Route {
        let model = CostModel(options: options)
        var legs: [RouteLeg] = []
        for (a, b) in zip(points, points.dropFirst()) {
            try Task.checkCancellation()
            let key = LegKey(from: a, to: b, options: options)
            if let cached = legCache[key] {
                legs.append(cached)
                continue
            }
            do {
                let leg = try router.leg(from: a, to: b, cost: model, isCancelled: { Task.isCancelled })
                remember(leg, for: key)
                legs.append(leg)
            } catch RoutingError.cancelled {
                throw CancellationError()
            }
        }
        return Route(legs: legs)
    }

    private func remember(_ leg: RouteLeg, for key: LegKey) {
        legCache[key] = leg
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            let old = cacheOrder.removeFirst()
            legCache[old] = nil
        }
    }

    /// Polylines of all roads with a known pavement condition, grouped into chunks
    /// of ~0.2° so that MapKit only draws the overlays that are on screen.
    func conditionChunks() -> [ConditionChunk] {
        let chunkSize = 0.2
        var buckets: [String: (RoadCondition, [[GeoCoordinate]])] = [:]
        graph.forEachGeometry { g, attributes in
            let condition = attributes.condition
            guard condition != .unknown else { return }
            let coords = graph.coordinates(ofGeometry: g)
            guard let first = coords.first else { return }
            let key = "\(Int(floor(first.latitude / chunkSize)))_\(Int(floor(first.longitude / chunkSize)))_\(condition.rawValue)"
            if buckets[key] == nil { buckets[key] = (condition, []) }
            buckets[key]!.1.append(coords)
        }
        return buckets.map { ConditionChunk(id: $0.key, condition: $0.value.0, polylines: $0.value.1) }
            .sorted { $0.id < $1.id }
    }
}
