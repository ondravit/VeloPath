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
    @State private var plannerOffset: CGFloat = 310

    var body: some View {
        Group {
            if coordinator.isLoading {
                SplashView()
            } else {
                ZStack {
                    // 🗺 Background map view
                    MapContainerView(roads: coordinator.roads)
                        .ignoresSafeArea()

                    TopPanel()

                    SidePanel()

                    // 🧱 Bottom route bar
                    VStack {
                        Spacer()
                        RoutePlannerPanel(offset: $plannerOffset)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
            }
        }
        .onAppear { coordinator.load() }
        .animation(.easeInOut(duration: 0.4), value: coordinator.isLoading)
    }
}
