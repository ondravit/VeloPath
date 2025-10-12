//
//  RoadsOverlay.swift
//  VeloPath
//
//  Created by Ondřej Vít on 10.10.2025.
//

import MapKit
import UIKit

// A lightweight overlay that just tells MapKit its visible region
final class RoadsOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect
    let roads: [RoadSegment]

    init(roads: [RoadSegment]) {
        self.roads = roads

        // Compute overall bounding box
        var minLat = 90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for r in roads {
            for c in r.coordinates {
                minLat = min(minLat, c.latitude)
                maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude)
                maxLon = max(maxLon, c.longitude)
            }
        }
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        boundingMapRect = MKMapRect(
            origin: MKMapPoint(x: topLeft.x, y: topLeft.y),
            size: MKMapSize(width: fabs(bottomRight.x - topLeft.x),
                            height: fabs(bottomRight.y - topLeft.y))
        )
        coordinate = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2,
                                            longitude: (minLon + maxLon)/2)
    }
}


/// Custom renderer that draws all roads in one CoreGraphics pass
final class RoadsOverlayRenderer: MKOverlayRenderer {
    let roads: [RoadSegment]

    init(overlay: RoadsOverlay) {
        self.roads = overlay.roads
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for road in roads {
            guard road.coordinates.count > 1 else { continue }

            let path = CGMutablePath()
            let first = MKMapPoint(road.coordinates[0])
            let startPoint = point(for: first)
            path.move(to: startPoint)

            for coord in road.coordinates.dropFirst() {
                let point = point(for: MKMapPoint(coord))
                path.addLine(to: point)
            }

            context.addPath(path)
            context.setStrokeColor(RoadsOverlayRenderer.color(for: road.condition).cgColor)
            context.setLineWidth(2.5 / zoomScale)
            context.strokePath()
        }
    }

    static func color(for condition: RoadSegment.RoadCondition) -> UIColor {
        switch condition {
        case .excellent: return .systemGreen
        case .good: return .green
        case .satisfactory: return .yellow
        case .unsatisfactory: return .orange
        case .emergency: return .red
        case .superemergency: return .purple
        case .unknown: return .gray
        }
    }
}
