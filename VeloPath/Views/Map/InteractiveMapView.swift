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
    @Binding var startCoord: CLLocationCoordinate2D?
    @Binding var endCoord: CLLocationCoordinate2D?
    let allRoads: [RoadSegment]
    let knownRoads: [RoadSegment]
    let unknownRoads: [RoadSegment]
    var userLocation: CLLocationCoordinate2D?
    
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
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Keep coordinator’s weak reference up to date (in case of re-creation)
        if context.coordinator.mapView !== uiView {
            context.coordinator.mapView = uiView
        }
        
        uiView.removeOverlays(uiView.overlays.compactMap { $0 as? RoadsOverlay })
        // …a znovu je přidej podle aktuálního režimu (prázdné pole = nic se nepřidá)
        addRoadOverlays(to: uiView)
        
        uiView.removeOverlays(uiView.overlays.filter { $0.title == "route" })
        // Draw new route
        if !routeCoords.isEmpty {
            let routeLine = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
            routeLine.title = "route"
            uiView.addOverlay(routeLine)
        }
        
        // Remove previous start/end annotations
        uiView.removeAnnotations(uiView.annotations)
        if let start = startCoord {
            let startAnno = MKPointAnnotation()
            startAnno.coordinate = start
            startAnno.title = "Start"
            uiView.addAnnotation(startAnno)
        }
        if let end = endCoord {
            let endAnno = MKPointAnnotation()
            endAnno.coordinate = end
            endAnno.title = "End"
            uiView.addAnnotation(endAnno)
        }
    }
    
    private func addRoadOverlays(to mapView: MKMapView) {
        
        // ⚙️ Neznámé silnice – šedé na pozadí
        if !unknownRoads.isEmpty {
            let unknownOverlay = RoadsOverlay(roads: unknownRoads)
            mapView.addOverlay(unknownOverlay, level: .aboveRoads)
        }

        // ✅ Známé silnice – barevné podle kvality
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
                selector: #selector(recenterMap),
                name: .recenterMap,
                object: nil
            )
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
            let mapView = gesture.view as! MKMapView
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            
            if parent.startCoord == nil {
                parent.startCoord = coord
            } else if parent.endCoord == nil {
                parent.endCoord = coord
                calculateRoute()
            } else {
                parent.startCoord = coord
                parent.endCoord = nil
                parent.routeCoords = []
            }
        }
        
        func calculateRoute() {
            guard let start = parent.startCoord, let end = parent.endCoord else { return }
            let routingService = RoutingService(roadSegments: parent.allRoads)
            
            Task {
                // Perform route calculation asynchronously
                let coords = await routingService.route(from: start, to: end)
                await MainActor.run {
                    parent.routeCoords = coords
                }
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
}
