import CoreLocation

final class RoutingService {

    private let graph: ImmutableGraph

    init(graph: ImmutableGraph) {
        self.graph = graph
    }

    /// Returns the coordinates of the best path from `start` to `end`.
    /// Runs A* on a background thread; safe to await from any context.
    func route(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        quality: Double
    ) async -> [CLLocationCoordinate2D] {
        let q = max(0, min(1, quality))

        guard let startNode = graph.nearestNode(to: start),
              let endNode   = graph.nearestNode(to: end) else { return [] }

        let graph = self.graph  // capture value type — safe to send across actors
        return await Task.detached(priority: .userInitiated) {
            let ids = AStar.findPath(in: graph, from: startNode.id, to: endNode.id, quality: q)
            return ids.compactMap { graph.node($0)?.coordinate }
        }.value
    }
}
