//
//  RoadSegment.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation

struct RoadSegment: Identifiable {
    let id: UUID = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let condition: RoadCondition
    
    enum RoadCondition: String {
        case excellent = "výborný"
        case good = "dobrý"
        case poor = "nevyhovující"
        case bad = "havarijní"
        case superbad = "SUPERhavarijní"
        case unknown
    }
}
