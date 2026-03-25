import CoreLocation

/// A* search on ImmutableGraph using Int64 node IDs.
enum AStar {

    static func findPath(
        in graph: ImmutableGraph,
        from startID: Int64,
        to goalID: Int64,
        quality: Double
    ) -> [Int64] {
        guard let startNode = graph.node(startID),
              let goalNode  = graph.node(goalID) else { return [] }

        var open     = PriorityQueue<OpenItem>(sort: { $0.f < $1.f })
        var cameFrom = [Int64: Int64]()
        var gScore   = [Int64: Double]()

        gScore[startID] = 0
        open.push(OpenItem(id: startID, f: heuristic(startNode, goalNode)))
        var inOpen: Set<Int64> = [startID]

        while let current = open.pop() {
            inOpen.remove(current.id)

            if current.id == goalID {
                return reconstructPath(cameFrom: cameFrom, end: goalID)
            }

            let gCurrent = gScore[current.id] ?? .infinity

            for edge in graph.neighbors(of: current.id) {
                let cost      = blendedCost(edge: edge, quality: quality)
                let tentative = gCurrent + cost

                if tentative < (gScore[edge.toNode] ?? .infinity) {
                    cameFrom[edge.toNode] = current.id
                    gScore[edge.toNode]   = tentative
                    if let toNode = graph.node(edge.toNode) {
                        let f = tentative + heuristic(toNode, goalNode)
                        if !inOpen.contains(edge.toNode) {
                            open.push(OpenItem(id: edge.toNode, f: f))
                            inOpen.insert(edge.toNode)
                        }
                    }
                }
            }
        }
        return []
    }

    // MARK: - Helpers

    /// Haversine straight-line distance (metres) — admissible heuristic.
    private static func heuristic(_ a: DBNode, _ b: DBNode) -> Double {
        a.coordinate.distance(to: b.coordinate)
    }

    /// Quality-blended edge cost.
    /// quality=0 → all edges treated equally (pure distance).
    /// quality=1 → condition penalties fully amplified (avoids bad roads).
    private static func blendedCost(edge: DBEdge, quality: Double) -> Double {
        let base     = 1.0
        let penalty  = DBEdge.conditionMultiplier(edge.condition)
        let strength = 5.0
        let mult     = (1 - quality) * base + quality * (base + (penalty - base) * strength)
        return edge.distanceM * mult
    }

    private static func reconstructPath(cameFrom: [Int64: Int64], end: Int64) -> [Int64] {
        var path = [end]
        var cur  = end
        while let prev = cameFrom[cur] {
            path.append(prev)
            cur = prev
        }
        return path.reversed()
    }

    private struct OpenItem {
        let id: Int64
        let f:  Double
    }
}

// MARK: - Priority Queue (min-heap)

struct PriorityQueue<T> {
    private var heap: [T] = []
    private let areSorted: (T, T) -> Bool

    init(sort: @escaping (T, T) -> Bool) { areSorted = sort }

    var isEmpty: Bool { heap.isEmpty }

    mutating func push(_ element: T) {
        heap.append(element)
        siftUp(heap.count - 1)
    }

    mutating func pop() -> T? {
        guard !heap.isEmpty else { return nil }
        heap.swapAt(0, heap.count - 1)
        let item = heap.removeLast()
        if !heap.isEmpty { siftDown(0) }
        return item
    }

    private mutating func siftUp(_ index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard areSorted(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(_ index: Int) {
        var parent = index
        while true {
            let left  = 2 * parent + 1
            let right = left + 1
            var best  = parent
            if left  < heap.count && areSorted(heap[left],  heap[best]) { best = left  }
            if right < heap.count && areSorted(heap[right], heap[best]) { best = right }
            guard best != parent else { return }
            heap.swapAt(parent, best)
            parent = best
        }
    }
}
