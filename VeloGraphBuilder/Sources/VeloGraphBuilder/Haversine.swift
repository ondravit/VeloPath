import Foundation

/// Pure-math Haversine distance. No CoreLocation dependency.
/// Uses the same earth radius constant as CLLocation internally.
enum Haversine {

    /// Returns great-circle distance in meters between two WGS-84 coordinates.
    static func distanceMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let R = 6_371_008.8  // IUGG mean radius, matches Apple's CLLocation closely
        let φ1 = lat1 * .pi / 180.0
        let φ2 = lat2 * .pi / 180.0
        let Δφ = (lat2 - lat1) * .pi / 180.0
        let Δλ = (lon2 - lon1) * .pi / 180.0
        let a = sin(Δφ / 2) * sin(Δφ / 2)
              + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return R * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    }
}
