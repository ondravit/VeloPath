//
//  Geo+Helpers.swift
//  RoadNavigationDemo
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
