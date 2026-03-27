import SwiftUI
import MapKit

struct InteractiveMapView: UIViewRepresentable {
    @Binding var segments: [DBSegment]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @Binding var routePlan: RoutePlan
    @Binding var startCoord: CLLocationCoordinate2D?
    @Binding var endCoord: CLLocationCoordinate2D?
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    let graph: ImmutableGraph?
    let knownSegments: [DBSegment]
    let unknownSegments: [DBSegment]
    var userLocation: CLLocationCoordinate2D?
    @Binding var qualityBalance: Double
    @Binding var routeDistance: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        mapView.showsUserLocation = true
        mapView.mapType = .standard

        // Road overlays will be populated by the first regionDidChangeAnimated
        // callback that fires after setRegion below.

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.mapTapped(_:)))
        mapView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.mapLongPressed(_:))
        )
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        mapView.setRegion(
            MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 50.4, longitude: 15.9),
                               span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)),
            animated: false
        )
        context.coordinator.refreshAnnotations(on: mapView)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if context.coordinator.mapView !== uiView {
            context.coordinator.mapView = uiView
        }

        // Road overlays are expensive — only replace them when the segment
        // data actually changes, not on every binding update (route, quality, etc.)
        context.coordinator.updateRoadOverlays(on: uiView,
                                               known: knownSegments,
                                               unknown: unknownSegments)

        uiView.removeOverlays(uiView.overlays.filter { $0.title == "route" })
        if !routeCoords.isEmpty {
            let line = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
            line.title = "route"
            uiView.addOverlay(line)
        }

        context.coordinator.refreshAnnotations(on: uiView)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveMapView
        weak var mapView: MKMapView?

        // Track last-rendered segment counts so road overlays are only
        // replaced when the actual data changes, not on every binding update.
        private var lastKnownCount   = -1
        private var lastUnknownCount = -1

        /// Prevents refreshAnnotations from interrupting an in-progress annotation drag.
        private var isDraggingAnnotation = false

        init(_ parent: InteractiveMapView) {
            self.parent = parent
            super.init()
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(recalculate),      name: .recalculateRoute,  object: nil)
            nc.addObserver(self, selector: #selector(recenterMap),      name: .recenterMap,       object: nil)
            nc.addObserver(self, selector: #selector(exportGPX),        name: .exportGPX,         object: nil)
            nc.addObserver(self, selector: #selector(confirmPlacement), name: .confirmPlacement,  object: nil)
            nc.addObserver(self, selector: #selector(cancelPlacement),  name: .cancelPlacement,   object: nil)
        }

        // MARK: Route calculation

        @objc private func recalculate() { calculateRoute() }

        func calculateRoute() {
            guard parent.routePlan.hasAtLeastStartAndEnd else {
                DispatchQueue.main.async {
                    self.parent.routeDistance = 0
                    self.parent.routeCoords   = []   // clear ghost polyline immediately
                }
                return
            }
            guard let graph = parent.graph else {
                print("⚠️ Graph not loaded yet — skipping route calculation")
                return
            }

            let coords = parent.routePlan.points
            let q      = parent.qualityBalance
            let service = RoutingService(graph: graph)

            Task {
                var fullRoute: [CLLocationCoordinate2D] = []
                for i in 0..<(coords.count - 1) {
                    let leg = await service.route(from: coords[i], to: coords[i + 1], quality: q)
                    if i > 0, !fullRoute.isEmpty { fullRoute.removeLast() }
                    fullRoute.append(contentsOf: leg)
                }

                let distance = fullRoute.totalDistanceInMeters()

                await MainActor.run {
                    self.parent.routeCoords   = fullRoute
                    self.parent.routeDistance = distance
                    if let mv = self.mapView {
                        mv.removeOverlays(mv.overlays.filter { $0.title == "route" })
                        if !fullRoute.isEmpty {
                            let line = MKPolyline(coordinates: fullRoute, count: fullRoute.count)
                            line.title = "route"
                            mv.addOverlay(line)
                        }
                        self.refreshAnnotations(on: mv)
                    }
                }
            }
        }

        // MARK: Map interaction

        @objc func mapTapped(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView,
                  !parent.isPlacingWaypoint else { return }
            let coord = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            parent.routePlan.points.append(coord)
            refreshAnnotations(on: mapView)
        }

        @objc private func confirmPlacement() {
            guard let mapView = mapView else { return }
            let center = mapView.centerCoordinate
            DispatchQueue.main.async {
                if let idx = self.parent.insertionIndex,
                   idx >= 0, idx <= self.parent.routePlan.points.count {
                    self.parent.routePlan.points.insert(center, at: idx)
                } else {
                    self.parent.routePlan.points.append(center)
                }
                self.parent.insertionIndex   = nil
                self.parent.isPlacingWaypoint = false
            }
            refreshAnnotations(on: mapView)
            recalculate()
        }

        @objc private func cancelPlacement() {
            DispatchQueue.main.async {
                self.parent.insertionIndex   = nil
                self.parent.isPlacingWaypoint = false
            }
        }

        // MARK: Long-press → insert waypoint on route

        @objc func mapLongPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MKMapView,
                  !parent.isPlacingWaypoint else { return }

            let touchPoint = gesture.location(in: mapView)
            let touchCoord = mapView.convert(touchPoint, toCoordinateFrom: mapView)

            // Bail if the long-press is near an existing waypoint annotation —
            // MapKit's own drag gesture will handle that case.
            for ann in mapView.annotations where !(ann is MKUserLocation) {
                let annPt = mapView.convert(ann.coordinate, toPointTo: mapView)
                if hypot(touchPoint.x - annPt.x, touchPoint.y - annPt.y) < 44 { return }
            }

            // Only insert if the touch is within ~25 screen points of the route polyline.
            let rCoords = parent.routeCoords
            guard rCoords.count >= 2 else { return }

            var minSegDist: CGFloat = .infinity
            for i in 0..<(rCoords.count - 1) {
                let p1 = mapView.convert(rCoords[i],     toPointTo: mapView)
                let p2 = mapView.convert(rCoords[i + 1], toPointTo: mapView)
                let d  = distanceFromPoint(touchPoint, toSegment: (p1, p2))
                if d < minSegDist { minSegDist = d }
            }
            guard minSegDist < 25 else { return }

            let insertIdx = findInsertionIndex(nearCoord: touchCoord)
            DispatchQueue.main.async {
                self.parent.routePlan.points.insert(touchCoord, at: insertIdx)
            }
            calculateRoute()
        }

        /// Returns the index at which a new waypoint should be inserted so that it
        /// falls on the correct leg of the existing route.
        private func findInsertionIndex(nearCoord coord: CLLocationCoordinate2D) -> Int {
            let waypoints  = parent.routePlan.points
            let routeCoords = parent.routeCoords
            guard waypoints.count >= 2, !routeCoords.isEmpty else { return waypoints.count }

            // Closest route-coordinate index to the pressed point.
            let pressedLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            var closestRouteIdx = 0
            var minDist = Double.infinity
            for (i, rc) in routeCoords.enumerated() {
                let d = CLLocation(latitude: rc.latitude, longitude: rc.longitude).distance(from: pressedLoc)
                if d < minDist { minDist = d; closestRouteIdx = i }
            }

            // For each waypoint find its nearest index in routeCoords.
            let wpRouteIdxs: [Int] = waypoints.map { wp in
                let wpLoc = CLLocation(latitude: wp.latitude, longitude: wp.longitude)
                var best = 0; var bestD = Double.infinity
                for (i, rc) in routeCoords.enumerated() {
                    let d = CLLocation(latitude: rc.latitude, longitude: rc.longitude).distance(from: wpLoc)
                    if d < bestD { bestD = d; best = i }
                }
                return best
            }

            // Find which leg [wpRouteIdxs[i]…wpRouteIdxs[i+1]] contains closestRouteIdx.
            for i in 0..<(wpRouteIdxs.count - 1) {
                let s = min(wpRouteIdxs[i], wpRouteIdxs[i + 1])
                let e = max(wpRouteIdxs[i], wpRouteIdxs[i + 1])
                if closestRouteIdx >= s && closestRouteIdx <= e { return i + 1 }
            }
            return waypoints.count - 1
        }

        /// Perpendicular distance from point `p` to a finite line segment `(a, b)`.
        private func distanceFromPoint(_ p: CGPoint, toSegment seg: (CGPoint, CGPoint)) -> CGFloat {
            let (a, b) = seg
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
            let len2 = ab.x * ab.x + ab.y * ab.y
            guard len2 > 0 else { return hypot(ap.x, ap.y) }
            let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / len2))
            let closest = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
            return hypot(p.x - closest.x, p.y - closest.y)
        }

        @objc private func recenterMap() {
            guard let mapView = mapView else { return }
            let coord = mapView.userLocation.coordinate
            guard coord.latitude != 0 || coord.longitude != 0 else { return }
            mapView.setRegion(
                MKCoordinateRegion(center: coord,
                                   span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
                animated: true
            )
        }

        @objc private func exportGPX() {
            guard !parent.routeCoords.isEmpty,
                  let url = GPXExporter.exportRoute(parent.routeCoords) else {
                print("⚠️ Žádná trasa k exportu.")
                return
            }
            guard let mapView = mapView,
                  var presenter = mapView.window?.rootViewController else { return }
            // Walk to the topmost presented VC — rootViewController may already be
            // presenting the sheet, making a direct present() call silently fail.
            while let next = presenter.presentedViewController {
                presenter = next
            }
            presenter.present(
                UIActivityViewController(activityItems: [url], applicationActivities: nil),
                animated: true
            )
        }

        // MARK: Annotations

        func refreshAnnotations(on mapView: MKMapView) {
            // Don't replace annotations while the user is mid-drag; it would cancel the gesture.
            guard !isDraggingAnnotation else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let points = self.parent.routePlan.points
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

                let annotations = points.enumerated().map { (i, coord) -> WaypointAnnotation in
                    let a = WaypointAnnotation()
                    a.coordinate     = coord
                    a.waypointIndex  = i
                    a.title = i == 0 ? "Start" : (i == points.count - 1 ? "Cíl" : "Bod \(i)")
                    return a
                }
                mapView.addAnnotations(annotations)
            }
        }

        // MARK: Road overlay management

        func updateRoadOverlays(on mapView: MKMapView,
                                 known: [DBSegment],
                                 unknown: [DBSegment]) {
            guard known.count != lastKnownCount || unknown.count != lastUnknownCount else { return }
            lastKnownCount   = known.count
            lastUnknownCount = unknown.count

            mapView.removeOverlays(mapView.overlays.compactMap { $0 as? RoadsOverlay })
            // Unknown (gray) drawn first so known quality segments render on top.
            if !unknown.isEmpty {
                mapView.addOverlay(RoadsOverlay(segments: unknown), level: .aboveRoads)
            }
            if !known.isEmpty {
                mapView.addOverlay(RoadsOverlay(segments: known), level: .aboveRoads)
            }
        }

        // MARK: Viewport segment loading

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            fetchViewportSegments(for: mapView)
        }

        private func fetchViewportSegments(for mapView: MKMapView) {
            let region = mapView.region
            let minLat = region.center.latitude  - region.span.latitudeDelta  / 2
            let maxLat = region.center.latitude  + region.span.latitudeDelta  / 2
            let minLon = region.center.longitude - region.span.longitudeDelta / 2
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2

            Task {
                let fetched = (try? await DatabaseService.shared.fetchSegments(
                    minLat: minLat, maxLat: maxLat,
                    minLon: minLon, maxLon: maxLon
                )) ?? []
                await MainActor.run {
                    self.parent.segments = fetched
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let roadsOverlay = overlay as? RoadsOverlay {
                return RoadsOverlayRenderer(overlay: roadsOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = .systemBlue
                r.lineWidth   = 3.5
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            DispatchQueue.main.async {
                self.parent.userLocation = userLocation.coordinate
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "routePoint"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation        = annotation
            view.canShowCallout    = true
            view.animatesWhenAdded = true
            view.displayPriority   = .required
            view.isDraggable       = true   // enables long-press → drag to move waypoint

            switch annotation.title {
            case "Start": view.markerTintColor = .systemGreen;  view.glyphImage = UIImage(systemName: "play.fill")
            case "Cíl":   view.markerTintColor = .systemRed;    view.glyphImage = UIImage(systemName: "flag.fill")
            default:      view.markerTintColor = .systemBlue
            }
            return view
        }

        func mapView(_ mapView: MKMapView,
                     annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                isDraggingAnnotation = true
            case .ending:
                isDraggingAnnotation = false
                guard let wp = view.annotation as? WaypointAnnotation else { return }
                let idx      = wp.waypointIndex
                let newCoord = wp.coordinate
                DispatchQueue.main.async {
                    guard self.parent.routePlan.points.indices.contains(idx) else { return }
                    self.parent.routePlan.points[idx] = newCoord
                }
                calculateRoute()
            case .canceling:
                isDraggingAnnotation = false
            @unknown default:
                break
            }
        }
    }
}

// MARK: - WaypointAnnotation

/// MKPointAnnotation subclass that carries the waypoint's index in routePlan.points,
/// so the drag-state delegate can update the correct element when the user moves it.
final class WaypointAnnotation: MKPointAnnotation {
    var waypointIndex: Int = 0
}

// MARK: - Notification names

extension Notification.Name {
    static let recenterMap       = Notification.Name("recenterMap")
    static let recalculateRoute  = Notification.Name("recalculateRoute")
    static let exportGPX         = Notification.Name("exportGPX")
    static let confirmPlacement  = Notification.Name("confirmPlacement")
    static let cancelPlacement   = Notification.Name("cancelPlacement")
}
