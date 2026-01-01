//
//  InteractiveMapView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import SwiftUI
import MapKit

struct InteractiveMapView: UIViewRepresentable {
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @Binding var routePlan: RoutePlan
    @Binding var startCoord: CLLocationCoordinate2D?
    @Binding var endCoord: CLLocationCoordinate2D?
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    let allRoads: [RoadSegment]
    let knownRoads: [RoadSegment]
    let unknownRoads: [RoadSegment]
    var userLocation: CLLocationCoordinate2D?
    @Binding var qualityBalance: Double
    @Binding var routeDistance: Double

    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        mapView.showsUserLocation = true
        mapView.mapType = .standard

        addRoadOverlays(to: mapView)

        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mapTapped(_:)))
        mapView.addGestureRecognizer(tapGesture)

        // Set initial region
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.4, longitude: 15.9),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        mapView.setRegion(region, animated: false)

        // Initialize annotations from any existing routePlan points
        context.coordinator.refreshAnnotations(on: mapView)

         return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Keep coordinator’s weak reference up to date (in case of re-creation)
        if context.coordinator.mapView !== uiView {
            context.coordinator.mapView = uiView
        }
        
        uiView.removeOverlays(uiView.overlays.compactMap { $0 as? RoadsOverlay })
        // Re-add road overlays
        addRoadOverlays(to: uiView)
        
        uiView.removeOverlays(uiView.overlays.filter { $0.title == "route" })
        // Draw new route
        if !routeCoords.isEmpty {
            let routeLine = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
            routeLine.title = "route"
            uiView.addOverlay(routeLine)
        }
        
        // Keep annotations synchronized with the authoritative `routePlan.points`.
        // Use coordinator helper so annotations are recreated consistently and do not get lost on overlay redraw.
        context.coordinator.refreshAnnotations(on: uiView)
    }
    
    private func addRoadOverlays(to mapView: MKMapView) {
        
        // Unknown roads – gray
        if !unknownRoads.isEmpty {
            let unknownOverlay = RoadsOverlay(roads: unknownRoads)
            mapView.addOverlay(unknownOverlay, level: .aboveRoads)
        }

        // Known roads – colored by condition
        if !knownRoads.isEmpty {
            let knownOverlay = RoadsOverlay(roads: knownRoads)
            mapView.addOverlay(knownOverlay, level: .aboveRoads)
        }
    }

    
    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveMapView
        weak var mapView: MKMapView?
        
        init(_ parent: InteractiveMapView) {
            self.parent = parent
            super.init()
            print("📡 Coordinator initialized, adding observer")
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(recalculate),
                name: .recalculateRoute,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(recenterMap),
                name: .recenterMap,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(exportGPX),
                name: .exportGPX,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(confirmPlacement),
                name: .confirmPlacement,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(cancelPlacement),
                name: .cancelPlacement,
                object: nil
            )
        }
        
        @objc private func exportGPX() {
            guard !parent.routeCoords.isEmpty,
                    let url = GPXExporter.exportRoute(parent.routeCoords) else {
                print("⚠️ Žádná trasa k exportu.")
                return
            }
            print("✅ GPX exported to: \(url.path)")
            
            // 💡 Volitelné: systémové sdílení (Share Sheet)
            if let mapView = mapView {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let controller = mapView.window?.rootViewController {
                    controller.present(activityVC, animated: true)
                }
            }
        }
        
        @objc private func recenterMap() {
            print("📩 Received .recenterMap notification")
                guard let mapView = mapView else {
                    print("⚠️ No mapView reference!")
                    return
                }
            let coord = mapView.userLocation.coordinate
                if coord.latitude == 0 && coord.longitude == 0 {
                    print("⚠️ Map has no valid user location yet.")
                    return
                }

                print("📍 Centering on \(coord.latitude), \(coord.longitude)")
                let region = MKCoordinateRegion(center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                mapView.setRegion(region, animated: true)
            }
        
        @objc func mapTapped(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            
            // Ignore taps while placing a waypoint
            if parent.isPlacingWaypoint {
                return
            }
            
            parent.routePlan.points.append(coord)
            
            // refresh/rebuild annotations from the updated routePlan
            refreshAnnotations(on: mapView)
         }
        
        @objc private func recalculate() { calculateRoute() }
        
        func calculateRoute() {
            guard parent.routePlan.hasAtLeastStartAndEnd else {
                DispatchQueue.main.async { self.parent.routeDistance = 0 }
                return
            }

            let coords = parent.routePlan.points
            let q = parent.qualityBalance
            let routingService = RoutingService(roadSegments: parent.allRoads)

            Task {
                var fullRoute: [CLLocationCoordinate2D] = []

                for i in 0..<(coords.count - 1) {
                    let segment = await routingService.route(from: coords[i], to: coords[i+1], quality: q)
                    if i > 0 { fullRoute.removeLast() } // spojení bodů
                    fullRoute.append(contentsOf: segment)
                }
                
                let distance = fullRoute.totalDistanceInMeters()

                await MainActor.run {
                    parent.routeCoords = fullRoute
                    self.parent.routeDistance = distance
                    // If we have a direct reference to the mapView, update overlays immediately so the route is visible
                    if let mv = self.mapView {
                        // remove existing route overlays
                        let existingRouteOverlays = mv.overlays.filter { $0.title == "route" }
                        if !existingRouteOverlays.isEmpty { mv.removeOverlays(existingRouteOverlays) }
                        if !fullRoute.isEmpty {
                            let routeLine = MKPolyline(coordinates: fullRoute, count: fullRoute.count)
                            routeLine.title = "route"
                            mv.addOverlay(routeLine)
                        }
                        // Also refresh annotations to ensure pins are present
                        self.refreshAnnotations(on: mv)
                    }
                 }
            }
        }

        @objc private func confirmPlacement() {
            guard let mapView = mapView else { return }
            let center = mapView.centerCoordinate
            print("📍 Confirm placement at center: \(center.latitude), \(center.longitude)")
            // insert at insertionIndex if provided, otherwise append
            DispatchQueue.main.async {
                if let idx = self.parent.insertionIndex, idx >= 0 && idx <= self.parent.routePlan.points.count {
                    self.parent.routePlan.points.insert(center, at: idx)
                } else {
                    self.parent.routePlan.points.append(center)
                }
                self.parent.insertionIndex = nil
                self.parent.isPlacingWaypoint = false
            }

            // rebuild annotations to include the newly inserted point
            refreshAnnotations(on: mapView)

             recalculate()
         }

        @objc private func cancelPlacement() {
            DispatchQueue.main.async {
                self.parent.insertionIndex = nil
                self.parent.isPlacingWaypoint = false
            }
        }

        // MARK: - MKMapViewDelegate
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let roadsOverlay = overlay as? RoadsOverlay {
                return RoadsOverlayRenderer(overlay: roadsOverlay)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 3.5
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
                let coord = userLocation.coordinate
                print("📍 MKMapView didUpdateUserLocation:", coord)
                DispatchQueue.main.async {
                    self.parent.userLocation = coord
                }
            }
        
        // MARK: - Updated Coordinator methods

        func refreshAnnotations(on mapView: MKMapView) {
            // Ensure we are on the main thread for UI updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let currentPoints = self.parent.routePlan.points
                let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
                

                mapView.removeAnnotations(existingAnnotations)

                let newAnnos = currentPoints.enumerated().map { (i, coord) -> MKPointAnnotation in
                    let anno = MKPointAnnotation()
                    anno.coordinate = coord
                    if i == 0 {
                        anno.title = "Start"
                    } else if i == currentPoints.count - 1 {
                        anno.title = "Cíl"
                    } else {
                        anno.title = "Bod \(i)"
                    }
                    return anno
                }
                
                mapView.addAnnotations(newAnnos)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 1. Skip user location blue dot
            if annotation is MKUserLocation { return nil }

            // 2. Use MKMarkerAnnotationView (modern style) or MKPinAnnotationView
            let identifier = "routePoint"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                annotationView?.animatesWhenAdded = true
            } else {
                annotationView?.annotation = annotation
            }

            // 3. Customize based on title
            if annotation.title == "Start" {
                annotationView?.markerTintColor = .systemGreen
                annotationView?.glyphImage = UIImage(systemName: "play.fill")
            } else if annotation.title == "Cíl" {
                annotationView?.markerTintColor = .systemRed
                annotationView?.glyphImage = UIImage(systemName: "flag.fill")
            } else {
                annotationView?.markerTintColor = .systemBlue
                //annotationView?.glyphColor = .w
            }
            
            // 4. Force visibility
            annotationView?.displayPriority = .required
            
            return annotationView
        }
    }
    
    
    // Color mapping
    func color(for condition: RoadSegment.RoadCondition) -> UIColor {
        switch condition {
        case .excellent: return UIColor(red: 0.0, green: 0.3, blue: 0.0, alpha: 1)
        case .good: return .green
        case .satisfactory: return .yellow
        case .unsatisfactory: return .orange
        case .emergency: return .red
        case .superemergency: return .purple
        case .unknown: return .gray
        }
    }
}

extension Notification.Name {
    static let recenterMap = Notification.Name("recenterMap")
    static let recalculateRoute = Notification.Name("recalculateRoute")
    static let exportGPX = Notification.Name("exportGPX")
    static let confirmPlacement = Notification.Name("confirmPlacement")
    static let cancelPlacement = Notification.Name("cancelPlacement")
}
