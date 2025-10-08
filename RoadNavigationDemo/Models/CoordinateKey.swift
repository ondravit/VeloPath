//
//  CoordinateKey.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import CoreLocation

/// Hashable key for coordinate dictionaries (safe tolerance)
struct CoordinateKey: Hashable {
    private let latKey: Int
    private let lonKey: Int
    
    init(coordinate: CLLocationCoordinate2D, precision: Double = 1e5) {
        // 1e5 ≈ 1m precision (0.00001 degrees)
        latKey = Int(coordinate.latitude * precision)
        lonKey = Int(coordinate.longitude * precision)
    }
    
    static func == (lhs: CoordinateKey, rhs: CoordinateKey) -> Bool {
        lhs.latKey == rhs.latKey && lhs.lonKey == rhs.lonKey
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(latKey)
        hasher.combine(lonKey)
    }
}

