
import SwiftUI
import MapKit

struct InteractiveMapView: UIViewRepresentable {
    let roads: [RoadSegment]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @Binding var startCoord: CLLocationCoordinate2D?
    @Binding var endCoord: CLLocationCoordinate2D?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .standard
        
        // Draw all roads as polylines
        for road in roads {
            let polyline = MKPolyline(coordinates: road.coordinates, count: road.coordinates.count)
            mapView.addOverlay(polyline)
        }
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mapTapped(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        // Set initial region
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.25, longitude: 15.75),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        mapView.setRegion(region, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Remove previous route overlay
        let oldRoutes = uiView.overlays.filter { $0.title == "route" }
        uiView.removeOverlays(oldRoutes)
        
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
    
    // MARK: - Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveMapView
        
        init(_ parent: InteractiveMapView) {
            self.parent = parent
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
            let routingService = RoutingService(roadSegments: parent.roads)
            
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
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            
            let renderer = MKPolylineRenderer(polyline: polyline)
            
            // Route polyline
            if overlay.title == "route" {
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
            }
            // Road polylines
            else if let road = parent.roads.first(where: { $0.matches(polyline: polyline) }) {
                renderer.strokeColor = parent.color(for: road.condition)
                renderer.lineWidth = 3
            } else {
                print("⚠️ Polyline not matched to any road!")
                renderer.strokeColor = .gray
                renderer.lineWidth = 3
            }
            
            return renderer
        }
    }
    
    
    // Color mapping
    func color(for condition: RoadSegment.RoadCondition) -> UIColor {
        switch condition {
        case .excellent: return .green
        case .good: return .systemGreen
        case .satisfactory: return .yellow
        case .unsatisfactory: return .orange
        case .emergency: return .red
        case .superemergency: return .purple
        case .unknown: return .gray
        }
    }

}
