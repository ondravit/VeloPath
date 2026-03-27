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
    /// Live drag offset: positive = user pulling panel down, negative = pulling up.
    /// Directly drives liveH in customBottomPanel; always reset to 0 on snap.
    @State private var dragOffset: CGFloat = 0

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
        ZStack(alignment: .bottom) {
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

            // Edge-to-edge bottom panel — replaces UISheetPresentationController to
            // eliminate the floating-pill side/bottom gaps that appear in partial detents.
            customBottomPanel

            // Crosshair overlay drawn last so it always appears above the bottom panel.
            if isPlacingWaypoint {
                placementOverlay
            }
        }
        .onChange(of: isPlacingWaypoint) { _, placing in
            if placing {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    plannerDetent = RoutePlannerPanel.collapsedDetent
                    dragOffset    = 0
                }
            }
        }
        // Safety reset: any programmatic detent change (e.g. auto-expand on 2nd waypoint)
        // should clear any residual drag offset so the panel sits at the right height.
        .onChange(of: plannerDetent) { _, _ in
            if dragOffset != 0 { dragOffset = 0 }
        }
    }

    // MARK: - Custom edge-to-edge bottom panel

    private var customBottomPanel: some View {
        GeometryReader { geo in
            let safe    = geo.safeAreaInsets.bottom
            let totalH  = geo.size.height
            let collapsedH = resolvedPanelHeight(for: RoutePlannerPanel.collapsedDetent, safe: safe, totalH: totalH)
            let mediumH    = resolvedPanelHeight(for: .medium, safe: safe, totalH: totalH)
            let baseH      = plannerDetent == RoutePlannerPanel.collapsedDetent ? collapsedH : mediumH
            // Clamp live height to [collapsedH, mediumH] — no large state exists.
            let liveH      = min(mediumH, max(collapsedH, baseH - dragOffset))

            VStack(spacing: 0) {
                // ── Drag handle ─────────────────────────────────────────────
                Capsule()
                    .fill(.secondary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { dragOffset = $0.translation.height }
                            .onEnded   { snapPanel($0, safe: safe, totalH: totalH) }
                    )

                // ── Route planner content ─────────────────────────────────
                RoutePlannerPanel(
                    routePlan:         $routePlan,
                    isPlacingWaypoint: $isPlacingWaypoint,
                    insertionIndex:    $insertionIndex,
                    qualityBalance:    $qualityBalance,
                    selectedDetent:    $plannerDetent,
                    routeDistance:     routeDistance,
                    userLocation:      locationManager.userLocation
                )
            }
            .frame(width: geo.size.width, height: liveH)
            // Content clip — keeps waypoint dots / scroll content inside the panel shape.
            .clipShape(PanelShape(radius: 20))
            // Background drawn as a shaped material fill so the blur samples the map
            // directly rather than first filling a rectangle and clipping it.
            .background {
                PanelShape(radius: 20)
                    .fill(.ultraThinMaterial)
            }
            // Subtle lift shadow so the panel reads as floating above the map.
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: -3)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: - Panel height & snap helpers

    /// Pixel height of the panel at the given detent.
    /// Only two states: collapsed peek and medium (~50 % screen).
    private func resolvedPanelHeight(for detent: PresentationDetent,
                                     safe: CGFloat,
                                     totalH: CGFloat) -> CGFloat {
        if detent == RoutePlannerPanel.collapsedDetent {
            return 15 + 100 + safe          // handle(15) + content(100) + home-indicator fill
        } else {                             // .medium
            return (totalH - safe) * 0.50 + safe
        }
    }

    /// Toggles between the two states based on drag direction.
    /// Positive translation/velocity → collapse; negative → expand to medium.
    private func snapPanel(_ drag: DragGesture.Value, safe: CGFloat, totalH: CGFloat) {
        let predicted = drag.predictedEndTranslation.height
        let actual    = drag.translation.height

        let goCollapse = predicted >  60 || actual >  80
        let goExpand   = predicted < -60 || actual < -80

        let target: PresentationDetent
        if goCollapse && !goExpand  { target = RoutePlannerPanel.collapsedDetent }
        else if goExpand && !goCollapse { target = .medium }
        else                            { target = plannerDetent }   // micro-gesture — stay

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            plannerDetent = target
            dragOffset    = 0
        }
    }

    // MARK: - Waypoint placement overlay

    private var placementOverlay: some View {
        GeometryReader { geo in
            // Position the confirm/cancel buttons above the collapsed panel so they
            // are never obscured. Collapsed panel height = 15 (handle) + 100 (content)
            // + safe-area bottom inset.
            let abovePanelPadding = 115 + geo.safeAreaInsets.bottom + 16

            ZStack {
                // Crosshair pin (non-interactive, dead-centred on screen)
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
                .allowsHitTesting(false)

                // Confirm / cancel buttons floating above the collapsed sheet
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
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, abovePanelPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Panel clip shape (top corners rounded, bottom edge flush)

private struct PanelShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: radius))
        p.addArc(center: CGPoint(x: radius, y: radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        p.addArc(center: CGPoint(x: rect.width - radius, y: radius), radius: radius,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}
