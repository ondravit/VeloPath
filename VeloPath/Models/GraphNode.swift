//
//  GraphNode.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import CoreLocation

struct GraphNode: Hashable, Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude.bitPattern)
        hasher.combine(coordinate.longitude.bitPattern)
    }
}
