import CoreLocation

/// Immutable in-memory graph loaded from the SQLite database.
/// Holds all nodes and the full adjacency list; spatial lookups via KDTree.
/// Built once at app startup; Sendable so it can be passed across actor boundaries.
struct ImmutableGraph: Sendable {

    /// All nodes keyed by their DB id for O(1) lookup during path reconstruction.
    let nodes: [Int64: DBNode]

    /// Adjacency list: fromNode.id → outgoing edges.
    let adjacency: [Int64: [DBEdge]]

    /// Spatial index for O(log n) nearest-node queries.
    let kdTree: KDTree

    // MARK: - Init

    init(nodes: [DBNode], edges: [DBEdge]) {
        var nodeMap = [Int64: DBNode](minimumCapacity: nodes.count)
        for n in nodes { nodeMap[n.id] = n }

        var adj = [Int64: [DBEdge]](minimumCapacity: nodes.count)
        for e in edges { adj[e.fromNode, default: []].append(e) }

        self.nodes    = nodeMap
        self.adjacency = adj
        self.kdTree   = KDTree(nodes: nodes)
    }

    // MARK: - Graph interface

    func neighbors(of nodeID: Int64) -> [DBEdge] {
        adjacency[nodeID] ?? []
    }

    func node(_ id: Int64) -> DBNode? {
        nodes[id]
    }

    func nearestNode(to coordinate: CLLocationCoordinate2D) -> DBNode? {
        kdTree.nearest(to: coordinate.latitude, coordinate.longitude)
    }
}
