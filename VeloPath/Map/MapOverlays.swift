import MapKit
import UIKit
import VeloCore

extension GeoCoordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension CLLocationCoordinate2D {
    var geo: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }
}

/// Pavement-condition overlay for one map chunk.
final class ConditionOverlay: MKMultiPolyline {
    var condition: RoadCondition = .unknown
}

/// The planned route; drawn twice (casing + line).
final class RouteOverlay: MKPolyline {
    enum Kind { case casing, line }
    var kind: Kind = .line
}

/// A waypoint marker.
final class WaypointAnnotation: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    var role: WaypointRole

    init(id: UUID, coordinate: CLLocationCoordinate2D, role: WaypointRole, title: String?) {
        self.id = id
        self.coordinate = coordinate
        self.role = role
        self.title = title
        super.init()
    }
}

enum MapStyling {
    static func configureMarker(_ view: MKMarkerAnnotationView, role: WaypointRole) {
        view.displayPriority = .required
        view.isDraggable = true
        view.canShowCallout = true
        view.animatesWhenAdded = true
        view.titleVisibility = .hidden
        view.subtitleVisibility = .hidden
        switch role {
        case .start:
            view.markerTintColor = UIColor(red: 0.10, green: 0.62, blue: 0.29, alpha: 1)
            view.glyphText = nil
            view.glyphImage = UIImage(systemName: "bicycle")
        case .via(let n):
            view.markerTintColor = .systemBlue
            view.glyphImage = nil
            view.glyphText = "\(n)"
        case .finish:
            view.markerTintColor = UIColor(red: 0.85, green: 0.18, blue: 0.20, alpha: 1)
            view.glyphText = nil
            view.glyphImage = UIImage(systemName: "flag.checkered")
        }
        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "trash"), for: .normal)
        delete.tintColor = .systemRed
        delete.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        delete.accessibilityLabel = "Odebrat bod"
        view.rightCalloutAccessoryView = delete
    }

    static func renderer(for overlay: MKOverlay) -> MKOverlayRenderer {
        if let o = overlay as? ConditionOverlay {
            let r = MKMultiPolylineRenderer(multiPolyline: o)
            r.strokeColor = o.condition.uiColor.withAlphaComponent(0.9)
            r.lineWidth = 3
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
        if let o = overlay as? RouteOverlay {
            let r = MKPolylineRenderer(polyline: o)
            r.lineCap = .round
            r.lineJoin = .round
            switch o.kind {
            case .casing:
                r.strokeColor = UIColor.white.withAlphaComponent(0.95)
                r.lineWidth = 9
            case .line:
                r.strokeColor = UIColor(named: "AccentColor") ?? .systemBlue
                r.lineWidth = 5.5
            }
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
