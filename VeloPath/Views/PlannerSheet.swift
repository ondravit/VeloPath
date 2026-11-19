import SwiftUI
import VeloCore

enum SearchTarget: Identifiable, Equatable {
    case append
    case replace(UUID)

    var id: String {
        switch self {
        case .append: return "append"
        case .replace(let id): return id.uuidString
        }
    }
}

struct PlannerSheet: View {
    @Environment(PlannerStore.self) private var store
    @Binding var detent: PresentationDetent
    @Binding var showsSettings: Bool
    @State private var searchTarget: SearchTarget?
    @State private var editMode: EditMode = .inactive
    @State private var confirmClear = false

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                RouteSummaryView(searchTarget: $searchTarget, onExpand: { detent = .medium })
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !store.waypoints.isEmpty {
                Section {
                    ForEach(Array(store.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                        WaypointRow(index: index, waypoint: waypoint,
                                    onSearch: { searchTarget = .replace(waypoint.id) })
                    }
                    .onDelete { store.removeWaypoints(atOffsets: $0) }
                    .onMove { store.moveWaypoints(fromOffsets: $0, toOffset: $1) }

                    Button {
                        searchTarget = .append
                    } label: {
                        Label("Přidat cíl nebo zastávku", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Body trasy")
                        Spacer()
                        if store.waypoints.count > 1 {
                            Button(editMode.isEditing ? "Hotovo" : "Upravit") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    if store.waypoints.count < 2 {
                        Text("Klepnutím do mapy přidáte další bod. Dlouhým stiskem na trase vložíte zastávku, body lze přetahovat.")
                    }
                }
            }

            Section {
                Picker("Priorita", selection: $store.options.surfacePriority) {
                    ForEach(SurfacePriority.allCases, id: \.self) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                Text(store.options.surfacePriority.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $store.options.avoidMainRoads) {
                    Label("Vyhnout se silnicím I. třídy", systemImage: "car.rear.road.lane")
                }
            } header: {
                Text("Preference trasy")
            }

            if let route = store.route {
                Section("Výškový profil") {
                    ElevationChartView(route: route)
                        .frame(height: 150)
                        .padding(.vertical, 4)
                }
                Section {
                    QualityBreakdownView(route: route)
                } header: {
                    Text("Povrch na trase")
                } footer: {
                    Text("Stav povrchu silnic II. a III. třídy pochází z měření správce silnic, u ostatních silnic z OpenStreetMap, pokud je k dispozici.")
                }
            }

            if store.waypoints.count >= 2 {
                Section {
                    Button {
                        store.reverseRoute()
                    } label: {
                        Label("Otočit směr trasy", systemImage: "arrow.up.arrow.down")
                    }
                    Button {
                        store.closeLoop()
                    } label: {
                        Label("Vrátit se na start (okruh)", systemImage: "arrow.triangle.capsulepath")
                    }
                    Button {
                        store.frameRoute()
                        detent = RootView.compactDetent
                    } label: {
                        Label("Zobrazit celou trasu", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Smazat trasu", systemImage: "trash")
                    }
                }
            }

            Section {
                Button {
                    showsSettings = true
                } label: {
                    Label("Nastavení a zdroje dat", systemImage: "info.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .confirmationDialog("Smazat celou trasu?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Smazat trasu", role: .destructive) { store.clearRoute() }
            Button("Zrušit", role: .cancel) {}
        }
        .sheet(item: $searchTarget) { target in
            PlaceSearchView(target: target)
                .environment(store)
        }
        .onChange(of: store.waypoints.count) { _, count in
            if count < 2, editMode.isEditing { editMode = .inactive }
        }
    }
}

// MARK: - Summary

struct RouteSummaryView: View {
    @Environment(PlannerStore.self) private var store
    @Binding var searchTarget: SearchTarget?
    var onExpand: () -> Void

    var body: some View {
        if store.waypoints.isEmpty {
            emptyState
        } else if let route = store.route {
            routeSummary(route)
        } else {
            pendingState
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kam pojedete?")
                .font(.title2.bold())
            HStack(spacing: 10) {
                Button {
                    searchTarget = .append
                } label: {
                    Label("Hledat místo", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    store.startFromCurrentLocation()
                } label: {
                    Image(systemName: "location.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Začít z mé polohy")
            }
            Text("Nebo klepněte do mapy – první bod je start, další body cíl a zastávky.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var pendingState: some View {
        HStack(spacing: 12) {
            if store.isRouting {
                ProgressView()
                Text("Počítám trasu…")
                    .font(.headline)
            } else if let error = store.routeError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.subheadline)
            } else {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.tint)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start je nastaven")
                        .font(.headline)
                    Text("Klepněte do mapy na cíl nebo ho vyhledejte.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !store.isRouting {
                Button {
                    searchTarget = .append
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Hledat cíl")
            }
        }
        .frame(minHeight: 60)
    }

    private func routeSummary(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.distance(route.distance))
                            .font(.title.bold())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if store.isRouting {
                            ProgressView().controlSize(.small)
                        }
                    }
                    HStack(spacing: 12) {
                        if let t = store.estimatedDuration {
                            Label(Format.duration(t), systemImage: "clock")
                        }
                        Label(Format.elevation(route.ascent), systemImage: "arrow.up.right")
                        Label(Format.elevation(route.descent), systemImage: "arrow.down.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(CompactLabelStyle())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
                if let url = store.gpxFileURL {
                    ShareLink(item: url, preview: SharePreview(store.routeTitle, image: Image(systemName: "bicycle"))) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("GPX")
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Exportovat trasu jako GPX")
                }
            }
            QualityBar(breakdown: route.conditionBreakdown, total: route.distance)
                .frame(height: 8)
                .onTapGesture(perform: onExpand)
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption.weight(.semibold))
            configuration.title
        }
    }
}

// MARK: - Waypoint row

struct WaypointRow: View {
    @Environment(PlannerStore.self) private var store
    let index: Int
    let waypoint: Waypoint
    var onSearch: () -> Void

    var body: some View {
        let role = WaypointRole.role(at: index, count: store.waypoints.count)
        Button {
            store.focus(on: waypoint)
        } label: {
            HStack(spacing: 12) {
                WaypointBadge(role: role)
                VStack(alignment: .leading, spacing: 2) {
                    Text(waypoint.name ?? "Načítám název…")
                        .font(.body)
                        .foregroundStyle(waypoint.name == nil ? .secondary : .primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(role.title)
                        if index > 0, let d = store.distanceFromStart(toWaypointAt: index) {
                            Text("·")
                            Text(Format.distance(d))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSearch()
            } label: {
                Label("Nahradit vyhledáním", systemImage: "magnifyingglass")
            }
            Button(role: .destructive) {
                store.removeWaypoint(waypoint.id)
            } label: {
                Label("Odebrat", systemImage: "trash")
            }
        }
    }
}

struct WaypointBadge: View {
    let role: WaypointRole

    var body: some View {
        ZStack {
            Circle().fill(color)
            switch role {
            case .start:
                Image(systemName: "bicycle").font(.caption.weight(.bold))
            case .via(let n):
                Text("\(n)").font(.caption.weight(.bold))
            case .finish:
                Image(systemName: "flag.checkered").font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch role {
        case .start: return Color(red: 0.10, green: 0.62, blue: 0.29)
        case .via: return .blue
        case .finish: return Color(red: 0.85, green: 0.18, blue: 0.20)
        }
    }
}
