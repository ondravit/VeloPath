import SwiftUI
import Combine
import CoreLocation

// MARK: - Coordinate equality (needed for onChange comparisons)

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - AppCoordinator

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var isLoading = true
    @Published var graph: ImmutableGraph?

    func load() {
        Task {
            do {
                // Hop to DatabaseService actor for each fetch (serialised on its DatabaseQueue).
                let nodes = try await DatabaseService.shared.loadAllNodes()
                let edges = try await DatabaseService.shared.loadAllEdges()

                // Build ImmutableGraph (allocates large dicts + KDTree) off the main thread.
                let builtGraph = await Task.detached(priority: .userInitiated) {
                    ImmutableGraph(nodes: nodes, edges: edges)
                }.value

                graph = builtGraph
            } catch {
                print("❌ Failed to load VeloGraph.sqlite: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var coordinator     = AppCoordinator()
    @StateObject private var locationManager = LocationManager()
    @State private var segments: [DBSegment]     = []
    @State private var plannerOffset: CGFloat    = 305
    @State private var showRoadsOverlay           = true
    @State private var roadDisplayMode: RoadDisplayMode = .knownOnly
    @State private var qualityBalance: Double    = 0.5
    @State private var routePlan                 = RoutePlan()
    @State private var isPlacingWaypoint         = false
    @State private var insertionIndex: Int?      = nil
    @State private var routeDistance: Double     = 0.0

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
            if oldValue == true, newValue == false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    locationManager.requestAuthorization()
                }
            }
        }
        .onChange(of: routePlan.points) { _, _ in
            NotificationCenter.default.post(name: .recalculateRoute, object: nil)
        }
    }

    // MARK: - Main interface

    private var mainInterface: some View {
        ZStack {
            MapContainerView(
                segments:         $segments,
                graph:            coordinator.graph,
                roadDisplayMode:  roadDisplayMode,
                userLocation:     locationManager.userLocation,
                qualityBalance:   $qualityBalance,
                routePlan:        $routePlan,
                isPlacingWaypoint: $isPlacingWaypoint,
                insertionIndex:   $insertionIndex,
                plannerOffset:    $plannerOffset,
                routeDistance:    $routeDistance
            )
            .ignoresSafeArea()

            TopPanel()
            SidePanel(roadDisplayMode: $roadDisplayMode)

            VStack {
                Spacer()
                if !isPlacingWaypoint {
                    RoutePlannerPanel(
                        offset:           $plannerOffset,
                        routePlan:        $routePlan,
                        isPlacingWaypoint: $isPlacingWaypoint,
                        insertionIndex:   $insertionIndex,
                        qualityBalance:   $qualityBalance,
                        routeDistance:    routeDistance
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if isPlacingWaypoint {
                placementOverlay
            }
        }
    }

    // MARK: - Waypoint placement overlay

    private var placementOverlay: some View {
        ZStack {
            // Crosshair pin
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Image(systemName: "mappin")
                        .font(.system(size: 34))
                        .foregroundColor(.red)
                        .offset(y: -17)
                        .shadow(color: .white, radius: 1)
                }
            }
            .allowsHitTesting(false)
            .zIndex(1)

            // Confirm / cancel buttons
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .cancelPlacement, object: nil)
                        insertionIndex   = nil
                        isPlacingWaypoint = false
                    } label: {
                        Text("Zrušit")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemBackground).opacity(0.95))
                            .cornerRadius(8).shadow(radius: 2)
                    }
                    Button {
                        NotificationCenter.default.post(name: .confirmPlacement, object: nil)
                        isPlacingWaypoint = false
                    } label: {
                        Text("OK")
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8).shadow(radius: 2)
                    }
                }
                .padding(.bottom, 34)
                .zIndex(2)
            }
        }
    }
}
