/// 2D KD-Tree over (lat, lon) for O(log n) nearest-neighbour lookup.
/// Built once from all graph nodes; read-only and Sendable.
struct KDTree: Sendable {

    private let root: Node?

    // Indirect so the recursive struct compiles.
    private indirect enum Node: Sendable {
        case leaf(DBNode)
        case branch(point: DBNode, left: Node?, right: Node?, axis: Int)
    }

    // MARK: - Build

    init(nodes: [DBNode]) {
        root = KDTree.build(nodes: nodes, depth: 0)
    }

    private static func build(nodes: [DBNode], depth: Int) -> Node? {
        guard !nodes.isEmpty else { return nil }
        if nodes.count == 1 { return .leaf(nodes[0]) }

        let axis = depth % 2  // 0 = lat, 1 = lon
        let sorted = nodes.sorted { axis == 0 ? $0.lat < $1.lat : $0.lon < $1.lon }
        let mid = sorted.count / 2

        let left  = build(nodes: Array(sorted[..<mid]),       depth: depth + 1)
        let right = build(nodes: Array(sorted[(mid + 1)...]), depth: depth + 1)

        return .branch(point: sorted[mid], left: left, right: right, axis: axis)
    }

    // MARK: - Query

    func nearest(to lat: Double, _ lon: Double) -> DBNode? {
        var best: DBNode?
        var bestSq = Double.infinity
        search(root, queryLat: lat, queryLon: lon, best: &best, bestSq: &bestSq)
        return best
    }

    private func search(
        _ node: Node?,
        queryLat: Double, queryLon: Double,
        best: inout DBNode?,
        bestSq: inout Double
    ) {
        guard let node else { return }

        switch node {
        case .leaf(let p):
            let d = sq(queryLat - p.lat, queryLon - p.lon)
            if d < bestSq { bestSq = d; best = p }

        case .branch(let p, let left, let right, let axis):
            let d = sq(queryLat - p.lat, queryLon - p.lon)
            if d < bestSq { bestSq = d; best = p }

            let diff = axis == 0 ? queryLat - p.lat : queryLon - p.lon
            let (near, far) = diff < 0 ? (left, right) : (right, left)

            search(near, queryLat: queryLat, queryLon: queryLon, best: &best, bestSq: &bestSq)

            // Only descend far branch if the splitting plane is closer than best so far.
            if diff * diff < bestSq {
                search(far, queryLat: queryLat, queryLon: queryLon, best: &best, bestSq: &bestSq)
            }
        }
    }

    // Squared degree-space distance — monotonic to real distance; sufficient for nearest lookup.
    @inline(__always)
    private func sq(_ dlat: Double, _ dlon: Double) -> Double {
        dlat * dlat + dlon * dlon
    }
}
