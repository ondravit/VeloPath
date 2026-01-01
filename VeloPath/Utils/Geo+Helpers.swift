//
//  Geo+Helpers.swift
//  VeloPath
//
//  Created by Ondřej Vít on 08.10.2025.
//

import CoreLocation

extension CLLocationCoordinate2D {
    /// Haversine distance in meters
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }

    /// Snap coordinate to grid (~N meters)
    func snapped(toMeters meters: Double) -> CLLocationCoordinate2D {
        let latMetersPerDeg = 111_320.0
        let lonMetersPerDeg = latMetersPerDeg * cos(latitude * .pi / 180.0)
        let latStep = meters / latMetersPerDeg
        let lonStep = meters / lonMetersPerDeg

        func snap(_ value: Double, step: Double) -> Double {
            (value / step).rounded() * step
        }

        return CLLocationCoordinate2D(
            latitude: snap(latitude, step: latStep),
            longitude: snap(longitude, step: lonStep)
        )
    }
}

extension Array where Element == CLLocationCoordinate2D {
    func totalDistanceInMeters() -> Double {
        guard self.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<self.count - 1 {
            let start = CLLocation(latitude: self[i].latitude, longitude: self[i].longitude)
            let end = CLLocation(latitude: self[i+1].latitude, longitude: self[i+1].longitude)
            total += start.distance(from: end)
        }
        return total
    }
}
