import SwiftUI
import VeloCore

struct RootView: View {
    @Environment(PlannerStore.self) private var store
    @State private var mapController = MapController()
    @State private var detent: PresentationDetent = RootView.compactDetent
    @State private var showsSettings = false

    static let compactDetent = PresentationDetent.height(150)

    var body: some View {
        ZStack(alignment: .top) {
            PlannerMapView(
                waypoints: store.waypoints,
                route: store.route,
                routeRevision: store.routeRevision,
                conditionChunks: store.conditionChunks,
                showsConditions: store.showsConditionLayer,
                mapStyle: store.mapStyle,
                bottomInset: store.sheetHeight,
                cameraRequest: store.cameraRequest,
                showsUserLocation: store.location.isAuthorized,
                controller: mapController,
                actions: MapActions(
                    tap: { store.addWaypoint(at: $0) },
                    longPress: { store.insertViaPoint(at: $0) },
                    moveWaypoint: { store.moveWaypoint($0, to: $1) },
                    deleteWaypoint: { store.removeWaypoint($0) },
                    conditionLayerShown: { shown in
                        if store.conditionLayerOnScreen != shown { store.conditionLayerOnScreen = shown }
                    }
                )
            )
            .ignoresSafeArea()

            MapControls(mapController: mapController, showsSettings: $showsSettings)

            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeInOut) { if store.toast == toast { store.toast = nil } }
                    }
            }

            if case .failed(let message) = store.phase {
                ContentUnavailableView("Mapová data nelze načíst", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .background(.background)
            }
        }
        .animation(.snappy, value: store.toast)
        .sheet(isPresented: .constant(true)) {
            PlannerSheet(detent: $detent, showsSettings: $showsSettings)
                .presentationDetents([RootView.compactDetent, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    store.sheetHeight = min(height, 520)
                }
                .sheet(isPresented: $showsSettings) {
                    SettingsView()
                        .environment(store)
                }
        }
        .onAppear(perform: applyLaunchArguments)
    }

    /// Lets CI capture screenshots of specific states.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiDetent"), i + 1 < args.count {
            switch args[i + 1] {
            case "medium": detent = .medium
            case "large": detent = .large
            default: detent = RootView.compactDetent
            }
        }
        if args.contains("-uiSettings") { showsSettings = true }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label(toast.message, systemImage: toast.systemImage)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule()
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct MapControls: View {
    @Environment(PlannerStore.self) private var store
    let mapController: MapController
    @Binding var showsSettings: Bool

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top) {
            if store.conditionLayerOnScreen {
                ConditionLegend()
                    .transition(.opacity)
            }
            Spacer()
            VStack(spacing: 10) {
                Menu {
                    Picker("Styl mapy", selection: $store.mapStyle) {
                        ForEach(MapStyleChoice.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Toggle(isOn: $store.showsConditionLayer) {
                        Label("Stav povrchu silnic", systemImage: "road.lanes")
                    }
                } label: {
                    controlIcon("square.2.layers.3d")
                }
                .accessibilityLabel("Vrstvy mapy")

                Button {
                    locate()
                } label: {
                    controlIcon("location.fill")
                }
                .accessibilityLabel("Moje poloha")

                Button {
                    showsSettings = true
                } label: {
                    controlIcon("gearshape")
                }
                .accessibilityLabel("Nastavení")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassCircle()
    }

    private func locate() {
        if store.location.isDenied {
            store.showToast("Přístup k poloze je vypnutý. Povolte ho v Nastavení iOS.", "location.slash")
            return
        }
        store.location.requestCurrentLocation { coordinate in
            if coordinate != nil { mapController.showUserLocation() }
        }
    }
}

/// Compact legend for the pavement-condition colours.
struct ConditionLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Povrch")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(RoadCondition.known, id: \.self) { c in
                    Capsule()
                        .fill(c.color)
                        .frame(width: 14, height: 6)
                }
            }
            Text("lepší → horší")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legenda: barvy silnic od výborného po havarijní stav povrchu")
    }
}
