//
//  ContentView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 10.10.2025.
//

import SwiftUI
import Combine

final class AppCoordinator: ObservableObject {
    @Published var isLoading = true
    @Published var roads: [RoadSegment] = []

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = GeoJSONService.loadRoads(from: "Stav_povrchu_silnic")
            DispatchQueue.main.async {
                self.roads = loaded
                self.isLoading = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var locationManager = LocationManager()
    @State private var plannerOffset: CGFloat = 305
    @State private var showRoadsOverlay = true
    @State private var recenterTrigger = false
    @State private var roadDisplayMode: RoadDisplayMode = .knownOnly
    @State private var qualityBalance: Double = 0.5


    

    var body: some View {
        Group {
            if coordinator.isLoading {
                SplashView()
                    .transition(.opacity)
            } else {
                mainInterface
                    .transition(.opacity)
            }
        }
        .onAppear { coordinator.load() }
        .animation(.easeInOut(duration: 0.5), value: coordinator.isLoading)
        .onChange(of: coordinator.isLoading) { oldValue, newValue in
            // 🧭 Only trigger after splash has *finished fading out*
            if oldValue == true && newValue == false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    locationManager.requestAuthorization()
                }
            }
        }
    }
    
    private var mainInterface: some View {
        ZStack {
            MapContainerView(
                roads: coordinator.roads,
                roadDisplayMode: roadDisplayMode,
                userLocation: locationManager.userLocation,
                qualityBalance: $qualityBalance
            )
            .ignoresSafeArea()

            TopPanel()
            SidePanel(roadDisplayMode: $roadDisplayMode)

            VStack {
                Spacer()
                RoutePlannerPanel(offset: $plannerOffset,
                                  qualityBalance: $qualityBalance)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
