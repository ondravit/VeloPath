import SwiftUI
import Combine
import CoreLocation

// MARK: - Coordinate equality (needed for onChange comparisons)

extension CLLocationCoordinate2D: @retroactive Equatable {
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
                let nodes = try await DatabaseService.shared.loadAllNodes()
                let edges = try await DatabaseService.shared.loadAllEdges()

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

    // Map state
    @State private var segments: [DBSegment]  = []
    @State private var roadDisplayMode: RoadDisplayMode = .knownOnly

    // Route state
    @State private var routePlan       = RoutePlan()
    @State private var qualityBalance: Double = 0.5
    @State private var routeDistance: Double  = 0.0

    // Waypoint placement state
    @State private var isPlacingWaypoint = false
    @State private var insertionIndex: Int? = nil

    // Bottom sheet state — starts collapsed
    @State private var plannerDetent: PresentationDetent = RoutePlannerPanel.collapsedDetent

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
            // Edge-to-edge map
            MapContainerView(
                segments:          $segments,
                graph:             coordinator.graph,
                roadDisplayMode:   roadDisplayMode,
                userLocation:      locationManager.userLocation,
                qualityBalance:    $qualityBalance,
                routePlan:         $routePlan,
                isPlacingWaypoint: $isPlacingWaypoint,
                insertionIndex:    $insertionIndex,
                routeDistance:     $routeDistance
            )
            .ignoresSafeArea()

            // Floating side buttons (layers + location)
            SidePanel(roadDisplayMode: $roadDisplayMode)

            // Crosshair overlay shown while the user is picking a waypoint position
            if isPlacingWaypoint {
                placementOverlay
            }
        }
        // Non-dismissible bottom sheet with three snap positions
        .sheet(isPresented: .constant(true)) {
            RoutePlannerPanel(
                routePlan:         $routePlan,
                isPlacingWaypoint: $isPlacingWaypoint,
                insertionIndex:    $insertionIndex,
                qualityBalance:    $qualityBalance,
                selectedDetent:    $plannerDetent,
                routeDistance:     routeDistance,
                userLocation:      locationManager.userLocation
            )
            .presentationDetents(
                [RoutePlannerPanel.collapsedDetent, .medium, .large],
                selection: $plannerDetent
            )
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationContentInteraction(.scrolls)
            .presentationBackground { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea() }
            .presentationCornerRadius(20)
            .interactiveDismissDisabled()
        }
        // Collapse the sheet whenever waypoint placement mode activates
        .onChange(of: isPlacingWaypoint) { _, placing in
            if placing { withAnimation { plannerDetent = RoutePlannerPanel.collapsedDetent } }
        }
    }

    // MARK: - Waypoint placement overlay

    private var placementOverlay: some View {
        ZStack {
            // Crosshair pin (non-interactive, centred on screen)
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

            // Confirm / cancel buttons above the home indicator
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .cancelPlacement, object: nil)
                        insertionIndex    = nil
                        isPlacingWaypoint = false
                    } label: {
                        Text("Zrušit")
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(radius: 2)
                    }
                    Button {
                        NotificationCenter.default.post(name: .confirmPlacement, object: nil)
                        isPlacingWaypoint = false
                    } label: {
                        Text("Potvrdit")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(radius: 2)
                    }
                }
                .padding(.bottom, 48)
                .zIndex(2)
            }
        }
    }
}
