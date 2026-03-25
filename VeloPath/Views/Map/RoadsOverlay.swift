import MapKit
import UIKit

// MARK: - Overlay

final class RoadsOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect
    let segments: [DBSegment]

    init(segments: [DBSegment]) {
        self.segments = segments

        var minLat = 90.0,  maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for s in segments {
            for c in s.coords {
                if c.latitude  < minLat { minLat = c.latitude  }
                if c.latitude  > maxLat { maxLat = c.latitude  }
                if c.longitude < minLon { minLon = c.longitude }
                if c.longitude > maxLon { maxLon = c.longitude }
            }
        }
        // Guard against empty input
        if minLat > maxLat { minLat = 0; maxLat = 0; minLon = 0; maxLon = 0 }

        let topLeft     = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        boundingMapRect = MKMapRect(
            origin: MKMapPoint(x: topLeft.x, y: topLeft.y),
            size:   MKMapSize(width:  abs(bottomRight.x - topLeft.x),
                              height: abs(bottomRight.y - topLeft.y))
        )
        coordinate = CLLocationCoordinate2D(latitude:  (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
    }
}

// MARK: - Renderer

final class RoadsOverlayRenderer: MKOverlayRenderer {
    private let segments: [DBSegment]

    init(overlay: RoadsOverlay) {
        self.segments = overlay.segments
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for seg in segments {
            guard seg.coords.count > 1 else { continue }

            let path = CGMutablePath()
            path.move(to: point(for: MKMapPoint(seg.coords[0])))
            for coord in seg.coords.dropFirst() {
                path.addLine(to: point(for: MKMapPoint(coord)))
            }

            context.addPath(path)
            context.setStrokeColor(RoadsOverlayRenderer.color(for: seg.condition).cgColor)
            context.setLineWidth(2.5 / zoomScale)
            context.strokePath()
        }
    }

    /// Condition integer encoding matches VeloGraphBuilder's SQLiteWriter (0–6).
    static func color(for condition: Int) -> UIColor {
        switch condition {
        case 0:  return UIColor(red: 0.0, green: 0.3, blue: 0.0, alpha: 1)  // excellent
        case 1:  return .systemGreen    // good
        case 2:  return .systemYellow   // satisfactory
        case 3:  return .systemOrange   // unsatisfactory
        case 4:  return .systemRed      // emergency
        case 5:  return .systemPurple   // superemergency
        default: return .systemGray     // unknown
        }
    }
}
