//
//  RoadSegment.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import Foundation
import CoreLocation
import MapKit

struct RoadSegment: Identifiable {
    let id: UUID = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let condition: RoadCondition
    
    enum RoadCondition: String {
        case excellent = "výborný"
        case good = "dobrý"
        case satisfactory = "vyhovující"
        case unsatisfactory = "nevyhovující"
        case emergency = "havarijní"
        case superemergency = "SUPERhavarijní"
        case unknown
    }
}

extension RoadSegment {
    func matches(polyline: MKPolyline) -> Bool {
        guard let first = coordinates.first, let last = coordinates.last else { return false }
        guard let polyFirst = polyline.coordinates.first, let polyLast = polyline.coordinates.last else { return false }
        
        func isClose(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            let latDiff = abs(a.latitude - b.latitude)
            let lonDiff = abs(a.longitude - b.longitude)
            return latDiff < 0.0001 && lonDiff < 0.0001 // ≈ 11 meters tolerance
        }
        
        return isClose(first, polyFirst) && isClose(last, polyLast)
    }
}
