import MapKit
import SwiftUI
import UIKit
import VeloCore

/// Callbacks from the map into the planner.
struct MapActions {
    var tap: (GeoCoordinate) -> Void
    var longPress: (GeoCoordinate) -> Void
    var moveWaypoint: (UUID, GeoCoordinate) -> Void
    var deleteWaypoint: (UUID) -> Void
    /// Reports whether the pavement-condition layer is currently drawn (it is hidden when zoomed out).
    var conditionLayerShown: (Bool) -> Void
}

/// Imperative access to the MKMapView for the floating map buttons.
@MainActor
final class MapController {
    weak var mapView: MKMapView?

    func showUserLocation() {
        guard let mapView else { return }
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: true)
    }

    var isFollowingUser: Bool { mapView?.userTrackingMode == .follow }
}

/// MapKit map with the route, the pavement-condition layer and draggable waypoints.
struct PlannerMapView: UIViewRepresentable {
    var waypoints: [Waypoint]
    var route: Route?
    var routeRevision: Int
    var conditionChunks: [ConditionChunk]
    var showsConditions: Bool
    var mapStyle: MapStyleChoice
    var bottomInset: CGFloat
    var cameraRequest: PlannerStore.CameraRequest?
    var showsUserLocation: Bool
    var controller: MapController
    var actions: MapActions

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.markerID)
        // Czech Republic as a sensible first frame until the graph is loaded.
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 50.3, longitude: 15.9),
                                         span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.6)), animated: false)
        context.coordinator.installGestures(on: map)
        controller.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        controller.mapView = map
        c.applyStyle(mapStyle, to: map)
        if map.layoutMargins.bottom != bottomInset {
            map.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        }
        if showsUserLocation, !map.showsUserLocation { map.showsUserLocation = true }
        c.syncConditionOverlays(on: map, chunks: conditionChunks, visible: showsConditions)
        c.syncRoute(on: map, route: route, revision: routeRevision)
        c.syncAnnotations(on: map, waypoints: waypoints)
        c.applyCamera(cameraRequest, on: map, bottomInset: bottomInset)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let markerID = "waypoint"
        var parent: PlannerMapView

        private var annotations: [UUID: WaypointAnnotation] = [:]
        private var routeOverlays: [RouteOverlay] = []
        private var appliedRouteRevision = -1
        private var conditionOverlays: [ConditionOverlay] = []
        private var appliedChunkIDs: [String] = []
        private var conditionsShown = false
        private var wantsConditions = false
        private var zoomAllowsConditions = true
        /// Above this latitude span the condition layer is hidden (too dense, too costly to draw).
        static let maxConditionSpan = 1.6
        private var appliedStyle: MapStyleChoice?
        private var appliedCameraID: UUID?
        private var draggingID: UUID?

        init(parent: PlannerMapView) {
            self.parent = parent
        }

        // MARK: Gestures

        func installGestures(on map: MKMapView) {
            let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            map.addGestureRecognizer(doubleTap)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: doubleTap)
            tap.delegate = self
            map.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.45
            longPress.delegate = self
            map.addGestureRecognizer(longPress)
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MKMapView else { return }
            if !map.selectedAnnotations.isEmpty {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
                return
            }
            let point = g.location(in: map)
            parent.actions.tap(map.convert(point, toCoordinateFrom: map).geo)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let point = g.location(in: map)
            parent.actions.longPress(map.convert(point, toCoordinateFrom: map).geo)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // never steal touches from markers, callouts or map controls
            var view = touch.view
            while let v = view {
                if v is MKAnnotationView || v is UIControl { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Style & camera

        func applyStyle(_ style: MapStyleChoice, to map: MKMapView) {
            guard appliedStyle != style else { return }
            appliedStyle = style
            switch style {
            case .standard:
                let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            case .hybrid:
                let config = MKHybridMapConfiguration(elevationStyle: .flat)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            }
        }

        func applyCamera(_ request: PlannerStore.CameraRequest?, on map: MKMapView, bottomInset: CGFloat) {
            guard let request, request.id != appliedCameraID else { return }
            // Before the first layout pass the map has no size and MapKit would zoom out to the whole world.
            guard map.bounds.width > 50, map.bounds.height > 200 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak map] in
                    guard let self, let map else { return }
                    self.applyCamera(request, on: map, bottomInset: self.parent.bottomInset)
                }
                return
            }
            appliedCameraID = request.id
            let bottom = min(max(bottomInset, 120) + 30, map.bounds.height * 0.55)
            let padding = UIEdgeInsets(top: 90, left: 44, bottom: bottom, right: 64)
            switch request.target {
            case .coordinates(let coords):
                guard !coords.isEmpty else { return }
                if coords.count == 1 {
                    let region = MKCoordinateRegion(center: coords[0].clCoordinate, latitudinalMeters: 2500, longitudinalMeters: 2500)
                    let rect = Self.mapRect(for: region)
                    map.setVisibleMapRect(rect, edgePadding: padding, animated: request.animated)
                } else {
                    var rect = MKMapRect.null
                    for c in coords {
                        let p = MKMapPoint(c.clCoordinate)
                        rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
                    }
                    let minSize = 2000.0 * MKMapPointsPerMeterAtLatitude(coords[0].latitude)
                    if rect.size.width < minSize || rect.size.height < minSize {
                        rect = rect.insetBy(dx: -minSize / 2, dy: -minSize / 2)
                    }
                    map.setVisibleMapRect(rect, edgePadding: padding, animated: request.animated)
                }
            case .region(let center, let latitudeDelta):
                let region = MKCoordinateRegion(center: center.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: latitudeDelta * 0.3))
                map.setRegion(region, animated: request.animated)
            case .bounds(let b):
                let tl = MKMapPoint(CLLocationCoordinate2D(latitude: b.maxLatitude, longitude: b.minLongitude))
                let br = MKMapPoint(CLLocationCoordinate2D(latitude: b.minLatitude, longitude: b.maxLongitude))
                let rect = MKMapRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
                map.setVisibleMapRect(rect, edgePadding: padding, animated: request.animated)
            }
        }

        private static func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
            let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                      longitude: region.center.longitude - region.span.longitudeDelta / 2))
            let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                      longitude: region.center.longitude + region.span.longitudeDelta / 2))
            return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }

        // MARK: Overlays

        func syncConditionOverlays(on map: MKMapView, chunks: [ConditionChunk], visible: Bool) {
            let ids = chunks.map(\.id)
            if ids != appliedChunkIDs {
                map.removeOverlays(conditionOverlays)
                conditionOverlays = chunks.map { chunk in
                    let lines = chunk.polylines.map { coords -> MKPolyline in
                        var cl = coords.map(\.clCoordinate)
                        return MKPolyline(coordinates: &cl, count: cl.count)
                    }
                    let overlay = ConditionOverlay(lines)
                    overlay.condition = chunk.condition
                    return overlay
                }
                appliedChunkIDs = ids
                conditionsShown = false
            }
            wantsConditions = visible
            refreshConditionVisibility(on: map)
        }

        private func refreshConditionVisibility(on map: MKMapView) {
            let show = wantsConditions && zoomAllowsConditions
            guard show != conditionsShown else { return }
            if show {
                for o in conditionOverlays { map.insertOverlay(o, at: 0, level: .aboveRoads) }
            } else {
                map.removeOverlays(conditionOverlays)
            }
            conditionsShown = show
            let report = parent.actions.conditionLayerShown
            DispatchQueue.main.async { report(show) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let allows = mapView.region.span.latitudeDelta < Self.maxConditionSpan
            if allows != zoomAllowsConditions {
                zoomAllowsConditions = allows
                refreshConditionVisibility(on: mapView)
            }
        }

        func syncRoute(on map: MKMapView, route: Route?, revision: Int) {
            guard revision != appliedRouteRevision else { return }
            appliedRouteRevision = revision
            map.removeOverlays(routeOverlays)
            routeOverlays = []
            guard let route, route.points.count >= 2 else { return }
            var coords = route.points.map(\.clCoordinate)
            let casing = RouteOverlay(coordinates: &coords, count: coords.count)
            casing.kind = .casing
            let line = RouteOverlay(coordinates: &coords, count: coords.count)
            line.kind = .line
            routeOverlays = [casing, line]
            map.addOverlays(routeOverlays, level: .aboveRoads)
        }

        func syncAnnotations(on map: MKMapView, waypoints: [Waypoint]) {
            let alive = Set(waypoints.map(\.id))
            for (id, annotation) in annotations where !alive.contains(id) {
                map.removeAnnotation(annotation)
                annotations[id] = nil
            }
            for (index, w) in waypoints.enumerated() {
                let role = WaypointRole.role(at: index, count: waypoints.count)
                let title = w.name ?? role.title
                if let existing = annotations[w.id] {
                    if draggingID != w.id {
                        let target = w.coordinate.clCoordinate
                        if existing.coordinate.latitude != target.latitude || existing.coordinate.longitude != target.longitude {
                            existing.coordinate = target
                        }
                    }
                    existing.title = title
                    existing.subtitle = role.title
                    if existing.role != role {
                        existing.role = role
                        if let view = map.view(for: existing) as? MKMarkerAnnotationView {
                            MapStyling.configureMarker(view, role: role)
                        }
                    }
                } else {
                    let a = WaypointAnnotation(id: w.id, coordinate: w.coordinate.clCoordinate, role: role, title: title)
                    a.subtitle = role.title
                    annotations[w.id] = a
                    map.addAnnotation(a)
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            MapStyling.renderer(for: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? WaypointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.markerID, for: a)
            if let marker = view as? MKMarkerAnnotationView {
                MapStyling.configureMarker(marker, role: a.role)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let a = view.annotation as? WaypointAnnotation else { return }
            mapView.deselectAnnotation(a, animated: true)
            parent.actions.deleteWaypoint(a.id)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let a = view.annotation as? WaypointAnnotation else { return }
            switch newState {
            case .starting:
                draggingID = a.id
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .ending:
                draggingID = nil
                view.setDragState(.none, animated: true)
                parent.actions.moveWaypoint(a.id, a.coordinate.geo)
            case .canceling:
                draggingID = nil
                view.setDragState(.none, animated: true)
            default:
                break
            }
        }
    }
}
