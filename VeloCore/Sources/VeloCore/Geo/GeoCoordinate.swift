import Foundation

/// WGS-84 coordinate in degrees. Platform independent (no CoreLocation dependency),
/// so the routing core can be tested on any platform.
public struct GeoCoordinate: Hashable, Codable, Sendable, CustomStringConvertible {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var description: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
}

public enum Geo {
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    @inlinable
    public static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        haversine(a.latitude, a.longitude, b.latitude, b.longitude)
    }

    @inlinable
    public static func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = p2 - p1
        let dl = (lon2 - lon1) * .pi / 180
        let s1 = sin(dp / 2)
        let s2 = sin(dl / 2)
        let h = s1 * s1 + cos(p1) * cos(p2) * s2 * s2
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Fast equirectangular distance, slightly scaled down so that it never exceeds the
    /// real length of a road between the two points. Used as the A* heuristic.
    @inlinable
    public static func heuristicDistance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let x = (lon2 - lon1) * .pi / 180 * cos((lat1 + lat2) / 2 * .pi / 180)
        let y = (lat2 - lat1) * .pi / 180
        return earthRadius * (x * x + y * y).squareRoot() * 0.995
    }
}

/// Axis-aligned bounding box in degrees.
public struct GeoBounds: Hashable, Codable, Sendable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude
        self.maxLongitude = maxLongitude
    }

    public init?(coordinates: [GeoCoordinate]) {
        guard let first = coordinates.first else { return nil }
        var b = GeoBounds(minLatitude: first.latitude, minLongitude: first.longitude,
                          maxLatitude: first.latitude, maxLongitude: first.longitude)
        for c in coordinates.dropFirst() { b.extend(c) }
        self = b
    }

    public mutating func extend(_ c: GeoCoordinate) {
        minLatitude = Swift.min(minLatitude, c.latitude)
        maxLatitude = Swift.max(maxLatitude, c.latitude)
        minLongitude = Swift.min(minLongitude, c.longitude)
        maxLongitude = Swift.max(maxLongitude, c.longitude)
    }

    public func contains(_ c: GeoCoordinate, marginDegrees m: Double = 0) -> Bool {
        c.latitude >= minLatitude - m && c.latitude <= maxLatitude + m
            && c.longitude >= minLongitude - m && c.longitude <= maxLongitude + m
    }

    public var center: GeoCoordinate {
        GeoCoordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }
}
