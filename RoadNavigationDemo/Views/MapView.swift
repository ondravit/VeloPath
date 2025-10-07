//
//  MapView.swift
//  RoadNavigationDemo
//
//  Created by Ondřej Vít on 07.10.2025.
//

import SwiftUI
import MapKit

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.25, longitude: 15.75),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    
    let roads: [RoadSegment]
    
    var body: some View {
        Map(position: .constant(.region(region))) {
            ForEach(roads) { road in
                MapPolyline(MKPolyline(coordinates: road.coordinates, count: road.coordinates.count))
                    .stroke(color(for: road.condition), lineWidth: 3)

            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    func color(for condition: RoadSegment.RoadCondition) -> Color {
        switch condition {
        case .excellent: return .green
        case .good: return .yellow
        case .poor: return .orange
        case .bad: return .red
        case .superbad: return .black
        case .unknown: return .gray
        }
    }
}
