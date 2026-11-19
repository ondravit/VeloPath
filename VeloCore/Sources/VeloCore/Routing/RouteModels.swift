import Foundation

/// A position on the road network (result of snapping a coordinate to the nearest road).
public struct NetworkPoint: Hashable, Sendable, Codable {
    /// Geometry (road stretch) id.
    public let geometry: Int
    /// Distance from the geometry's start, in metres.
    public let offset: Double
    /// The snapped coordinate on the road.
    public let coordinate: GeoCoordinate
    /// Distance between the original query coordinate and the road.
    public let distanceFromQuery: Double

    public init(geometry: Int, offset: Double, coordinate: GeoCoordinate, distanceFromQuery: Double) {
        self.geometry = geometry
        self.offset = offset
        self.coordinate = coordinate
        self.distanceFromQuery = distanceFromQuery
    }
}

/// A stretch of the route with uniform road attributes.
public struct RoutePiece: Hashable, Sendable {
    public let attributes: EdgeAttributes
    public let surveyYear: Int?
    /// Range of indices into `RouteLeg.points` / `Route.points` covered by this piece (inclusive).
    public let pointRange: ClosedRange<Int>
    public let length: Double
}

public struct RouteLeg: Sendable {
    public let start: NetworkPoint
    public let end: NetworkPoint
    public let points: [GeoCoordinate]
    /// Elevation in metres at each point (`nil` outside DEM coverage).
    public let elevations: [Double?]
    /// Distance from the leg start at each point, in metres.
    public let distances: [Double]
    public let pieces: [RoutePiece]
    public let distance: Double
    public let ascent: Double
    public let descent: Double
    /// Internal routing cost (weighted metres).
    public let cost: Double
    /// Number of graph nodes the search expanded (diagnostics).
    public let expandedNodes: Int
}

public struct ElevationSample: Hashable, Sendable {
    /// Distance from the route start in metres.
    public let distance: Double
    public let elevation: Double
}

/// A complete multi-leg route.
public struct Route: Sendable {
    public let legs: [RouteLeg]
    public let points: [GeoCoordinate]
    public let elevations: [Double?]
    public let distances: [Double]
    public let pieces: [RoutePiece]
    /// Index of the first point of every leg in `points`.
    public let legStartIndices: [Int]
    public let distance: Double
    public let ascent: Double
    public let descent: Double

    public init(legs: [RouteLeg]) {
        self.legs = legs
        var pts: [GeoCoordinate] = []
        var ele: [Double?] = []
        var dist: [Double] = []
        var pieces: [RoutePiece] = []
        var legStarts: [Int] = []
        var offset = 0.0
        for leg in legs {
            // consecutive legs share their joint point – drop the duplicate
            let skip = pts.isEmpty ? 0 : 1
            let base = pts.count - skip
            legStarts.append(max(0, base))
            if leg.points.count > skip {
                pts.append(contentsOf: leg.points[skip...])
                ele.append(contentsOf: leg.elevations[skip...])
                dist.append(contentsOf: leg.distances[skip...].map { $0 + offset })
            }
            for p in leg.pieces {
                pieces.append(RoutePiece(attributes: p.attributes, surveyYear: p.surveyYear,
                                         pointRange: (p.pointRange.lowerBound + base)...(p.pointRange.upperBound + base),
                                         length: p.length))
            }
            offset += leg.distance
        }
        points = pts
        elevations = ele
        distances = dist
        self.pieces = pieces
        legStartIndices = legStarts
        distance = legs.reduce(0) { $0 + $1.distance }
        ascent = legs.reduce(0) { $0 + $1.ascent }
        descent = legs.reduce(0) { $0 + $1.descent }
    }

    /// Distance in metres per pavement condition.
    public var conditionBreakdown: [RoadCondition: Double] {
        pieces.reduce(into: [:]) { $0[$1.attributes.condition, default: 0] += $1.length }
    }

    /// Distance in metres per surface type.
    public var surfaceBreakdown: [Surface: Double] {
        pieces.reduce(into: [:]) { $0[$1.attributes.surface, default: 0] += $1.length }
    }

    /// Distance in metres per road class.
    public var roadClassBreakdown: [RoadClass: Double] {
        pieces.reduce(into: [:]) { $0[$1.attributes.roadClass, default: 0] += $1.length }
    }

    public var maxElevation: Double? { elevations.compactMap { $0 }.max() }
    public var minElevation: Double? { elevations.compactMap { $0 }.min() }

    /// Evenly spaced elevation profile with at most `maxSamples` samples (for charts).
    public func elevationProfile(maxSamples: Int = 240) -> [ElevationSample] {
        guard distance > 0, points.count >= 2, maxSamples >= 2 else { return [] }
        let step = distance / Double(maxSamples - 1)
        var out: [ElevationSample] = []
        out.reserveCapacity(maxSamples)
        var j = 0
        for i in 0..<maxSamples {
            let d = min(distance, Double(i) * step)
            while j + 1 < distances.count - 1 && distances[j + 1] < d { j += 1 }
            let k = min(j + 1, distances.count - 1)
            guard let e0 = elevations[j], let e1 = elevations[k] else { continue }
            let span = distances[k] - distances[j]
            let t = span > 0 ? (d - distances[j]) / span : 0
            out.append(ElevationSample(distance: d, elevation: e0 + (e1 - e0) * min(1, max(0, t))))
        }
        return out
    }

    /// Index of the leg whose geometry is closest to `coordinate`, and the distance to it.
    public func nearestLeg(to coordinate: GeoCoordinate) -> (leg: Int, distance: Double)? {
        guard points.count >= 2 else { return nil }
        let kx = cos(coordinate.latitude * .pi / 180) * 111_320.0
        let ky = 110_574.0
        var best = Double.infinity
        var bestIndex = 0
        for i in 0..<(points.count - 1) {
            let ax = (points[i].longitude - coordinate.longitude) * kx
            let ay = (points[i].latitude - coordinate.latitude) * ky
            let bx = (points[i + 1].longitude - coordinate.longitude) * kx
            let by = (points[i + 1].latitude - coordinate.latitude) * ky
            let dx = bx - ax, dy = by - ay
            let l2 = dx * dx + dy * dy
            let t = l2 > 0 ? min(1, max(0, -(ax * dx + ay * dy) / l2)) : 0
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            if d < best {
                best = d
                bestIndex = i
            }
        }
        var leg = 0
        for (k, start) in legStartIndices.enumerated() where start <= bestIndex { leg = k }
        return (leg, best)
    }
}
