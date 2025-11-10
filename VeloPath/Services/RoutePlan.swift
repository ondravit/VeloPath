//
//  RoutePlan.swift
//  VeloPath
//
//  Created by Ondřej Vít on 10.11.2025.
//

import CoreLocation

struct RoutePlan {
    var points: [CLLocationCoordinate2D] = []  // Start, Waypoints, End
    var quality: Double = 0.5

    var hasAtLeastStartAndEnd: Bool { points.count >= 2 }
}
