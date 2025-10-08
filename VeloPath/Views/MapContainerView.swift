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
    @State private var roads: [RoadSegment] = []
    @State private var isLoading = true
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    
    var body: some View {
        ZStack {
            if isLoading {
                SplashView()
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.6), value: isLoading)
            } else {
                InteractiveMapView(
                    roads: roads,
                    routeCoords: $routeCoords,
                    startCoord: $startCoord,
                    endCoord: $endCoord
                )
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.8), value: isLoading)
            }
        }
        .task {
            await loadRoadsAsync()
        }
    }
    
    private func loadRoadsAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = GeoJSONService.loadRoads(from: "Stav_povrchu_silnic")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.roads = loaded
                    self.isLoading = false
                    continuation.resume()
                }
            }
        }
    }
}
