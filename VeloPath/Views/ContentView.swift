//
//  ContentView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 10.10.2025.
//

import SwiftUI
import Combine
import CoreLocation

// Check if two coordinates are equal
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

final class AppCoordinator: ObservableObject {
    @Published var isLoading = true
    @Published var roads: [RoadSegment] = []

    // Load roads data asynchronously
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
    @State private var routeDistance: Double = 0.0

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
            // Request location authorization after loading completes
            if oldValue == true && newValue == false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    locationManager.requestAuthorization()
                }
            }
        }
        // Recalculate route when waypoints change
        .onChange(of: routePlan.points) { _, _ in
            NotificationCenter.default.post(name: .recalculateRoute, object: nil)
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
                plannerOffset: $plannerOffset,
                routeDistance: $routeDistance
            )
            .ignoresSafeArea()

            TopPanel()
            SidePanel(roadDisplayMode: $roadDisplayMode)

            VStack {
                Spacer()
                // Hide the planner panel completely while placing a waypoint
                if !isPlacingWaypoint {
                    RoutePlannerPanel(
                        offset: $plannerOffset,
                        routePlan: $routePlan,
                        isPlacingWaypoint: $isPlacingWaypoint,
                        insertionIndex: $insertionIndex,
                        qualityBalance: $qualityBalance,
                        routeDistance: routeDistance
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // Marker + OK/Cancel overlay (above map and above the planner panel)
            if isPlacingWaypoint {
                let screen = UIScreen.main.bounds

                VStack(spacing: 8) {
                        // Pin-only marker
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 5, height: 5)
                            
                            Image(systemName: "mappin") // Nebo zkuste plnější "mappin.circle.fill"
                                .font(.system(size: 34)) // Zvětšeno pro lepší manipulaci
                                .foregroundColor(.red)
                                // Klíčová úprava: Posun nahoru o cca polovinu velikosti
                                // Protože font je 34, posun -17 zajistí, že špička sedí na středu
                                .offset(y: -17)
                                // Volitelné: Bílý stín pro lepší viditelnost na tmavé mapě
                                .shadow(color: .white, radius: 1)
                        }
                    }
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
