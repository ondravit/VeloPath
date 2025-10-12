//
//  MapContainerView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 07.10.2025.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapContainerView: View {
    let roads: [RoadSegment]
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    
    var body: some View {
        ZStack {
            InteractiveMapView(
                roads: roads,
                routeCoords: $routeCoords,
                startCoord: $startCoord,
                endCoord: $endCoord
            )
            .edgesIgnoringSafeArea(.all)
        }
    }
}
