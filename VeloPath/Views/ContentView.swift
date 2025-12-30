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
    @State private var routePlan = RoutePlan()
    @State private var isPlacingWaypoint = false
    @State private var insertionIndex: Int? = nil

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
                qualityBalance: $qualityBalance,
                routePlan: $routePlan,
                isPlacingWaypoint: $isPlacingWaypoint,
                insertionIndex: $insertionIndex,
                plannerOffset: $plannerOffset
            )
            .ignoresSafeArea()

            TopPanel()
            SidePanel(roadDisplayMode: $roadDisplayMode)

            VStack {
                Spacer()
                // Hide the planner panel completely while placing a waypoint
                if !isPlacingWaypoint {
                    RoutePlannerPanel(offset: $plannerOffset,
                                      routePlan: $routePlan,
                                      isPlacingWaypoint: $isPlacingWaypoint,
                                      insertionIndex: $insertionIndex,
                                      qualityBalance: $qualityBalance)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // Marker + OK/Cancel overlay (above map and above the planner panel)
            if isPlacingWaypoint {
                let screen = UIScreen.main.bounds

                VStack(spacing: 8) {
                    // Pin-only marker: clear pointer using system symbol inside a white circle
                    ZStack {
                        Image(systemName: "mappin")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                    }
                }
                .offset(x: 0, y: 0.05)
                .allowsHitTesting(false)
                .zIndex(1)

                // Bottom-aligned accept / cancel buttons so they remain selectable when the panel is hidden
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: .cancelPlacement, object: nil)
                            insertionIndex = nil
                            isPlacingWaypoint = false
                        }) {
                            Text("Zrušit")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground).opacity(0.95))
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }

                        Button(action: {
                            NotificationCenter.default.post(name: .confirmPlacement, object: nil)
                            isPlacingWaypoint = false
                        }) {
                            Text("OK")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }
                    }
                    .padding(.bottom, 34)
                    .zIndex(2)
                }
            }
        }
    }
}
