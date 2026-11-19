import Foundation

public enum RoutingError: Error, LocalizedError, Equatable {
    case noRoute
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noRoute: return "Mezi body nevede žádná cesta vhodná pro silniční kolo."
        case .cancelled: return "Výpočet trasy byl zrušen."
        }
    }
}

/// A* router over a `RoadGraph`.
///
/// A `Router` keeps reusable search buffers and is **not** thread-safe – use one instance
/// per thread / actor. The graph itself can be shared.
public final class Router {
    public let graph: RoadGraph

    // Search state, sized nodeCount. `stamp[i] == generation` marks valid entries.
    private var gScore: [Double]
    private var parentEdge: [UInt32]
    private var parentNode: [UInt32]
    private var stamp: [UInt32]
    private var closedStamp: [UInt32]
    private var generation: UInt32 = 0
    private var heap = BinaryHeap(capacity: 4096)

    static let fromSourceForward: UInt32 = .max
    static let fromSourceBackward: UInt32 = .max - 1

    public init(graph: RoadGraph) {
        self.graph = graph
        let n = graph.nodeCount
        gScore = [Double](repeating: .infinity, count: n)
        parentEdge = [UInt32](repeating: 0, count: n)
        parentNode = [UInt32](repeating: 0, count: n)
        stamp = [UInt32](repeating: 0, count: n)
        closedStamp = [UInt32](repeating: 0, count: n)
    }

    // MARK: - Snapping

    /// Snaps a coordinate to the nearest routable road within `maxDistance` metres.
    public func snap(_ coordinate: GeoCoordinate, maxDistance: Double = 400) -> NetworkPoint? {
        let g = graph
        guard g.gridRows > 0, g.gridCols > 0 else { return nil }
        let lat = coordinate.latitude, lon = coordinate.longitude
        let kx = cos(lat * .pi / 180) * 111_320.0
        let ky = 110_574.0
        let cellMeters = min(g.gridCellLat * ky, g.gridCellLon * kx)
        let row = Int(floor((lat - g.gridOriginLat) / g.gridCellLat))
        let col = Int(floor((lon - g.gridOriginLon) / g.gridCellLon))

        var best: (dist: Double, geom: Int, seg: Int, t: Double)?
        var visited = Set<Int>()
        var ring = 0
        while true {
            for r in (row - ring)...(row + ring) {
                for c in (col - ring)...(col + ring) {
                    // only the outline of the ring is new
                    if ring > 0 && abs(r - row) != ring && abs(c - col) != ring { continue }
                    guard r >= 0, r < g.gridRows, c >= 0, c < g.gridCols else { continue }
                    let cell = r * g.gridCols + c
                    for k in Int(g.gridCellStart[cell])..<Int(g.gridCellStart[cell + 1]) {
                        let geom = Int(g.gridItems[k])
                        guard visited.insert(geom).inserted else { continue }
                        let range = g.coordinateRange(ofGeometry: geom)
                        var px = (Double(g.coordLon[range.lowerBound]) / 1e7 - lon) * kx
                        var py = (Double(g.coordLat[range.lowerBound]) / 1e7 - lat) * ky
                        for i in (range.lowerBound + 1)..<range.upperBound {
                            let qx = (Double(g.coordLon[i]) / 1e7 - lon) * kx
                            let qy = (Double(g.coordLat[i]) / 1e7 - lat) * ky
                            let dx = qx - px, dy = qy - py
                            let l2 = dx * dx + dy * dy
                            let t = l2 > 0 ? min(1, max(0, -(px * dx + py * dy) / l2)) : 0
                            let sx = px + t * dx, sy = py + t * dy
                            let d = (sx * sx + sy * sy).squareRoot()
                            if best == nil || d < best!.dist {
                                best = (d, geom, i - 1 - range.lowerBound, t)
                            }
                            px = qx
                            py = qy
                        }
                    }
                }
            }
            let covered = Double(ring) * cellMeters
            if let b = best, b.dist <= covered { break }
            if covered > maxDistance { break }
            ring += 1
        }
        guard let b = best, b.dist <= maxDistance else { return nil }

        // distance along the geometry, rescaled to its stored length
        let pts = g.coordinates(ofGeometry: b.geom)
        var along = 0.0
        var total = 0.0
        for i in 0..<(pts.count - 1) {
            let l = Geo.distance(pts[i], pts[i + 1])
            if i < b.seg { along += l } else if i == b.seg { along += l * b.t }
            total += l
        }
        let stored = g.length(ofGeometry: b.geom)
        let offset = total > 0 ? along / total * stored : 0
        let a = pts[b.seg], c = pts[b.seg + 1]
        let snapped = GeoCoordinate(latitude: a.latitude + b.t * (c.latitude - a.latitude),
                                    longitude: a.longitude + b.t * (c.longitude - a.longitude))
        return NetworkPoint(geometry: b.geom, offset: offset, coordinate: snapped, distanceFromQuery: b.dist)
    }

    // MARK: - Routing

    private struct TargetEntry {
        var node: Int
        var cost: Double
        var reversed: Bool
    }

    private enum Solution {
        case direct(reversed: Bool)
        case viaNode(Int, reversed: Bool)
    }

    /// Computes the best route between two snapped points.
    ///
    /// - Parameter isCancelled: polled periodically; return `true` to abort with `RoutingError.cancelled`.
    public func leg(from source: NetworkPoint, to target: NetworkPoint, cost: CostModel,
                    isCancelled: () -> Bool = { false }) throws -> RouteLeg {
        let g = graph
        generation &+= 1
        if generation == 0 {
            // wrapped around – reset stamps
            for i in stamp.indices { stamp[i] = 0; closedStamp[i] = 0 }
            generation = 1
        }
        let gen = generation
        heap.removeAll()

        let srcDirs = g.allowedDirections(ofGeometry: source.geometry)
        let dstDirs = g.allowedDirections(ofGeometry: target.geometry)
        let srcFactor = cost.multiplier(g.attributes(ofGeometry: source.geometry))
        let dstFactor = cost.multiplier(g.attributes(ofGeometry: target.geometry))
        let srcLen = g.length(ofGeometry: source.geometry)
        let dstLen = g.length(ofGeometry: target.geometry)
        let (srcU, srcV) = g.endpoints(ofGeometry: source.geometry)
        let (dstU, dstV) = g.endpoints(ofGeometry: target.geometry)
        let tLat = target.coordinate.latitude
        let tLon = target.coordinate.longitude

        var bestTotal = Double.infinity
        var solution: Solution?

        if source.geometry == target.geometry {
            if target.offset >= source.offset, srcDirs.forward {
                bestTotal = (target.offset - source.offset) * srcFactor
                solution = .direct(reversed: false)
            } else if target.offset < source.offset, srcDirs.backward {
                bestTotal = (source.offset - target.offset) * srcFactor
                solution = .direct(reversed: true)
            }
        }

        var targets: [TargetEntry] = []
        if dstDirs.forward { targets.append(TargetEntry(node: dstU, cost: target.offset * dstFactor, reversed: false)) }
        if dstDirs.backward {
            let c = (dstLen - target.offset) * dstFactor
            if let i = targets.firstIndex(where: { $0.node == dstV }) {
                if c < targets[i].cost { targets[i] = TargetEntry(node: dstV, cost: c, reversed: true) }
            } else {
                targets.append(TargetEntry(node: dstV, cost: c, reversed: true))
            }
        }

        var expanded = 0
        try gScore.withUnsafeMutableBufferPointer { gsBuffer in
            try parentEdge.withUnsafeMutableBufferPointer { peBuffer in
                try parentNode.withUnsafeMutableBufferPointer { pnBuffer in
                    try stamp.withUnsafeMutableBufferPointer { stBuffer in
                        try closedStamp.withUnsafeMutableBufferPointer { clBuffer in
                            // Buffer pointers have reference semantics; plain copies avoid capturing inout parameters.
                            let gs = gsBuffer, pe = peBuffer, pn = pnBuffer, st = stBuffer, cl = clBuffer
                            func h(_ node: Int) -> Double {
                                Geo.heuristicDistance(Double(g.nodeLat[node]) / 1e7, Double(g.nodeLon[node]) / 1e7, tLat, tLon)
                            }
                            func seed(_ node: Int, _ c: Double, _ marker: UInt32) {
                                if st[node] != gen || c < gs[node] {
                                    st[node] = gen
                                    gs[node] = c
                                    pe[node] = marker
                                    heap.push(c + h(node), UInt32(node))
                                }
                            }
                            if srcDirs.forward { seed(srcV, (srcLen - source.offset) * srcFactor, Router.fromSourceForward) }
                            if srcDirs.backward { seed(srcU, source.offset * srcFactor, Router.fromSourceBackward) }

                            let firstEdge = g.firstEdge
                            let edgeTarget = g.edgeTarget
                            let edgeGeometry = g.edgeGeometry
                            let geomLength = g.geomLength
                            let geomAttr = g.geomAttr
                            let table = cost.table

                            while let top = heap.pop() {
                                if top.key >= bestTotal { break }
                                let u = Int(top.value)
                                if cl[u] == gen { continue }
                                cl[u] = gen
                                expanded += 1
                                if expanded & 2047 == 0, isCancelled() { throw RoutingError.cancelled }
                                let gu = gs[u]
                                for t in targets where t.node == u && gu + t.cost < bestTotal {
                                    bestTotal = gu + t.cost
                                    solution = .viaNode(u, reversed: t.reversed)
                                }
                                for k in Int(firstEdge[u])..<Int(firstEdge[u + 1]) {
                                    let v = Int(edgeTarget[k])
                                    if cl[v] == gen { continue }
                                    let geom = Int(edgeGeometry[k] & ~RoadGraph.reversedBit)
                                    let nc = gu + Double(geomLength[geom]) * table[Int(geomAttr[geom] & 0x1FFF)]
                                    if st[v] != gen || nc < gs[v] {
                                        st[v] = gen
                                        gs[v] = nc
                                        pe[v] = UInt32(k)
                                        pn[v] = UInt32(u)
                                        heap.push(nc + h(v), UInt32(v))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let solution else { throw RoutingError.noRoute }

        // Reconstruct the sequence of (geometry, reversed, from, to) traversals.
        var steps: [(geom: Int, reversed: Bool, from: Double, to: Double)] = []
        switch solution {
        case .direct(let reversed):
            steps = [(source.geometry, reversed, source.offset, target.offset)]
        case .viaNode(let node, let reversed):
            var rev: [(geom: Int, reversed: Bool, from: Double, to: Double)] = []
            rev.append((target.geometry, reversed, reversed ? dstLen : 0, target.offset))
            var u = node
            while true {
                let marker = parentEdge[u]
                if marker == Router.fromSourceForward {
                    rev.append((source.geometry, false, source.offset, srcLen))
                    break
                }
                if marker == Router.fromSourceBackward {
                    rev.append((source.geometry, true, source.offset, 0))
                    break
                }
                let k = Int(marker)
                let ref = g.edgeGeometry[k]
                let geom = Int(ref & ~RoadGraph.reversedBit)
                let isRev = ref & RoadGraph.reversedBit != 0
                let len = g.length(ofGeometry: geom)
                rev.append((geom, isRev, isRev ? len : 0, isRev ? 0 : len))
                u = Int(parentNode[u])
            }
            steps = rev.reversed()
        }
        return buildLeg(steps: steps, source: source, target: target, cost: bestTotal, expanded: expanded)
    }

    private func buildLeg(steps: [(geom: Int, reversed: Bool, from: Double, to: Double)],
                          source: NetworkPoint, target: NetworkPoint, cost: Double, expanded: Int) -> RouteLeg {
        let g = graph
        var points: [GeoCoordinate] = []
        var elevations: [Double?] = []
        var distances: [Double] = []
        var pieces: [RoutePiece] = []
        var travelled = 0.0
        var ascent = 0.0
        var descent = 0.0

        for step in steps {
            let length = abs(step.to - step.from)
            if length < 0.01 && steps.count > 1 { continue }
            let sub = extract(geometry: step.geom, from: step.from, to: step.to)
            let startIndex: Int
            if points.isEmpty {
                startIndex = 0
                points.append(contentsOf: sub.points)
                elevations.append(contentsOf: sub.elevations)
                distances.append(contentsOf: sub.distances.map { $0 + travelled })
            } else {
                startIndex = points.count - 1
                points.append(contentsOf: sub.points.dropFirst())
                elevations.append(contentsOf: sub.elevations.dropFirst())
                distances.append(contentsOf: sub.distances.dropFirst().map { $0 + travelled })
            }
            let attrs = g.attributes(ofGeometry: step.geom)
            let total = g.length(ofGeometry: step.geom)
            let fraction = total > 0 ? length / total : 0
            let climb = g.climb(ofGeometry: step.geom)
            if step.reversed {
                ascent += climb.descent * fraction
                descent += climb.ascent * fraction
            } else {
                ascent += climb.ascent * fraction
                descent += climb.descent * fraction
            }
            let endIndex = max(startIndex, points.count - 1)
            if let last = pieces.last, last.attributes == attrs, last.surveyYear == g.surveyYear(ofGeometry: step.geom),
               last.pointRange.upperBound == startIndex {
                pieces[pieces.count - 1] = RoutePiece(attributes: attrs, surveyYear: last.surveyYear,
                                                      pointRange: last.pointRange.lowerBound...endIndex,
                                                      length: last.length + length)
            } else {
                pieces.append(RoutePiece(attributes: attrs, surveyYear: g.surveyYear(ofGeometry: step.geom),
                                         pointRange: startIndex...endIndex, length: length))
            }
            travelled += length
        }
        if points.isEmpty {
            points = [source.coordinate, target.coordinate]
            elevations = [nil, nil]
            distances = [0, 0]
        }
        // Prefer climbing computed from the route profile with a small hysteresis: it filters the
        // residual DEM noise (forest canopy in the surface model) the per-road sums still contain.
        let known = elevations.compactMap { $0 }
        if known.count >= 2, known.count * 10 >= elevations.count * 9 {
            let climb = Router.climb(of: known, threshold: Router.climbThreshold)
            ascent = climb.ascent
            descent = climb.descent
        }
        return RouteLeg(start: source, end: target, points: points, elevations: elevations, distances: distances,
                        pieces: pieces, distance: travelled, ascent: ascent, descent: descent, cost: cost,
                        expandedNodes: expanded)
    }

    /// Part of a geometry between two offsets (metres along the stored direction).
    /// When `from > to` the points are returned in reverse order.
    func extract(geometry geom: Int, from: Double, to: Double) -> (points: [GeoCoordinate], elevations: [Double?], distances: [Double]) {
        let g = graph
        let range = g.coordinateRange(ofGeometry: geom)
        let count = range.count
        var cum = [Double](repeating: 0, count: count)
        for i in 1..<count {
            cum[i] = cum[i - 1] + Geo.distance(g.coordinate(at: range.lowerBound + i - 1), g.coordinate(at: range.lowerBound + i))
        }
        let stored = g.length(ofGeometry: geom)
        let scale = cum[count - 1] > 0 ? stored / cum[count - 1] : 1
        for i in 0..<count { cum[i] *= scale }

        func interpolate(_ d: Double) -> (GeoCoordinate, Double?) {
            let d = min(max(d, 0), stored)
            var i = 0
            while i + 1 < count - 1 && cum[i + 1] < d { i += 1 }
            let span = cum[i + 1] - cum[i]
            let t = span > 0 ? (d - cum[i]) / span : 0
            let a = g.coordinate(at: range.lowerBound + i)
            let b = g.coordinate(at: range.lowerBound + i + 1)
            let c = GeoCoordinate(latitude: a.latitude + t * (b.latitude - a.latitude),
                                  longitude: a.longitude + t * (b.longitude - a.longitude))
            var e: Double?
            if let ea = g.elevation(at: range.lowerBound + i), let eb = g.elevation(at: range.lowerBound + i + 1) {
                e = ea + t * (eb - ea)
            }
            return (c, e)
        }

        let lo = min(from, to), hi = max(from, to)
        var pts: [GeoCoordinate] = []
        var eles: [Double?] = []
        var ds: [Double] = []
        let (startC, startE) = interpolate(lo)
        pts.append(startC); eles.append(startE); ds.append(lo)
        for i in 0..<count where cum[i] > lo + 0.01 && cum[i] < hi - 0.01 {
            pts.append(g.coordinate(at: range.lowerBound + i))
            eles.append(g.elevation(at: range.lowerBound + i))
            ds.append(cum[i])
        }
        let (endC, endE) = interpolate(hi)
        pts.append(endC); eles.append(endE); ds.append(hi)

        if from > to {
            pts.reverse()
            eles.reverse()
            ds = ds.reversed().map { hi - $0 }
        } else {
            ds = ds.map { $0 - lo }
        }
        return (pts, eles, ds)
    }

    /// Minimum elevation change (metres) counted as climbing or descending.
    public static let climbThreshold = 4.0

    /// Total ascent and descent of an elevation series, ignoring oscillations below `threshold`.
    public static func climb(of elevations: [Double], threshold: Double) -> (ascent: Double, descent: Double) {
        guard var reference = elevations.first else { return (0, 0) }
        var ascent = 0.0
        var descent = 0.0
        for e in elevations.dropFirst() {
            let delta = e - reference
            if delta >= threshold {
                ascent += delta
                reference = e
            } else if delta <= -threshold {
                descent -= delta
                reference = e
            }
        }
        return (ascent, descent)
    }

    // MARK: - Multi-leg convenience

    /// Routes through all `waypoints` in order. Waypoints must already be snapped.
    public func route(through waypoints: [NetworkPoint], options: RoutingOptions,
                      isCancelled: () -> Bool = { false }) throws -> Route {
        let model = CostModel(options: options)
        var legs: [RouteLeg] = []
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            legs.append(try leg(from: a, to: b, cost: model, isCancelled: isCancelled))
        }
        return Route(legs: legs)
    }
}
