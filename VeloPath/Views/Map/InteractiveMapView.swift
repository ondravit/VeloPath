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
                DispatchQueue.main.async { self.parent.routeDistance = 0 }
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
            if let mapView = mapView,
               let root = mapView.window?.rootViewController {
                root.present(UIActivityViewController(activityItems: [url],
                                                      applicationActivities: nil),
                             animated: true)
            }
        }

        // MARK: Annotations

        func refreshAnnotations(on mapView: MKMapView) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let points = self.parent.routePlan.points
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

                let annotations = points.enumerated().map { (i, coord) -> MKPointAnnotation in
                    let a = MKPointAnnotation()
                    a.coordinate = coord
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
            view.annotation       = annotation
            view.canShowCallout   = true
            view.animatesWhenAdded = true
            view.displayPriority  = .required

            switch annotation.title {
            case "Start": view.markerTintColor = .systemGreen;  view.glyphImage = UIImage(systemName: "play.fill")
            case "Cíl":   view.markerTintColor = .systemRed;    view.glyphImage = UIImage(systemName: "flag.fill")
            default:      view.markerTintColor = .systemBlue
            }
            return view
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let recenterMap       = Notification.Name("recenterMap")
    static let recalculateRoute  = Notification.Name("recalculateRoute")
    static let exportGPX         = Notification.Name("exportGPX")
    static let confirmPlacement  = Notification.Name("confirmPlacement")
    static let cancelPlacement   = Notification.Name("cancelPlacement")
}
