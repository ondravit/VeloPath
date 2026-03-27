import SwiftUI
import CoreLocation

struct RoutePlannerPanel: View {

    // MARK: - Bindings & input

    @Binding var routePlan: RoutePlan
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    @Binding var qualityBalance: Double
    @Binding var selectedDetent: PresentationDetent
    let routeDistance: Double
    let userLocation: CLLocationCoordinate2D?   // for "Use current location"

    // MARK: - Local state

    @State private var showAbout = false
    @State private var recalcTask: Task<Void, Never>? = nil

    /// The collapsed / peek detent — referenced by ContentView.
    static let collapsedDetent = PresentationDetent.height(100)

    // MARK: - Body
    //
    // Two states only:
    //   collapsed  ~115 pt  → drag-indicator + vertically centred header + distance
    //   medium     ~50 %    → header + distance + scrollable waypoint list + slider
    //
    var body: some View {
        VStack(spacing: 0) {

            if selectedDetent == Self.collapsedDetent {

                // ── Collapsed: vertically centre the summary rows ──────────
                Spacer(minLength: 0)
                headerRow
                distanceRow
                Spacer(minLength: 0)

            } else {

                // ── Medium ─────────────────────────────────────────────────
                headerRow
                distanceRow
                Divider()

                if routePlan.points.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(routePlan.points.indices, id: \.self) { i in
                            TimelineRow(
                                index:        i,
                                totalCount:   routePlan.points.count,
                                coord:        routePlan.points[i],
                                onDelete: {
                                    withAnimation {
                                        if routePlan.points.indices.contains(i) {
                                            routePlan.points.remove(at: i)
                                        }
                                    }
                                },
                                onInsertAfter: {
                                    insertionIndex    = i + 1
                                    isPlacingWaypoint = true
                                },
                                onInsertCurrentLocationAfter: userLocation.map { loc in
                                    {
                                        withAnimation {
                                            routePlan.points.insert(loc, at: i + 1)
                                        }
                                    }
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            routePlan.points.move(fromOffsets: from, toOffset: to)
                            NotificationCenter.default.post(name: .recalculateRoute, object: nil)
                        }

                        appendButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    // Fill all remaining height above the quality slider.
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                }

                Divider()
                qualitySliderSection
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
            }

        }
        .onChange(of: routePlan.points.count) { oldCount, newCount in
            if newCount >= 2, oldCount < 2, selectedDetent == Self.collapsedDetent {
                withAnimation { selectedDetent = .medium }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 16) {
            Text("Plánovač trasy")
                .font(.headline)
            Spacer()

            // Reverse — only meaningful with 2+ waypoints
            if routePlan.points.count >= 2 {
                Button {
                    withAnimation { routePlan.points.reverse() }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Clear all — shown whenever any waypoint exists
            if !routePlan.points.isEmpty {
                Button {
                    withAnimation { routePlan.points.removeAll() }
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.large)
                        .foregroundStyle(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
            }

            Button {
                NotificationCenter.default.post(name: .exportGPX, object: nil)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Distance / hint row

    private var distanceRow: some View {
        Group {
            if routeDistance > 0 {
                Text(formatDistance(routeDistance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            } else {
                Label("Klepněte na mapu a přidejte trasu", systemImage: "hand.tap")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, selectedDetent == Self.collapsedDetent ? 0 : 10)
        .animation(.default, value: routeDistance)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Přidejte start a cíl klepnutím na mapu")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            // Quick-start: set the first point directly to the user's GPS position.
            if let loc = userLocation {
                Button {
                    withAnimation { routePlan.points.append(loc) }
                } label: {
                    Label("Nastavit start na aktuální polohu", systemImage: "location.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Append button

    private var appendButton: some View {
        HStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 2, height: 20)
                .padding(.leading, 9)
                .padding(.trailing, 21)

            if let loc = userLocation {
                // Show a Menu so the user can choose between map placement or current location.
                Menu {
                    Button {
                        insertionIndex    = routePlan.points.count
                        isPlacingWaypoint = true
                    } label: {
                        Label("Vybrat na mapě", systemImage: "map")
                    }
                    Button {
                        withAnimation {
                            routePlan.points.append(loc)
                        }
                    } label: {
                        Label("Použít aktuální polohu", systemImage: "location.fill")
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Přidat zastávku")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    insertionIndex    = routePlan.points.count
                    isPlacingWaypoint = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Přidat zastávku")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, -8)
    }

    // MARK: - Quality slider

    private var qualitySliderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nejkratší")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Nejkvalitnější")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $qualityBalance, in: 0...1)
                .tint(.blue)
                .onChange(of: qualityBalance) { _, _ in
                    recalcTask?.cancel()
                    recalcTask = Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        NotificationCenter.default.post(name: .recalculateRoute, object: nil)
                    }
                }
            Text("Poměr: \(Int(qualityBalance * 100)) % kvalita")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }
}

// MARK: - Timeline row

struct TimelineRow: View {
    let index: Int
    let totalCount: Int
    let coord: CLLocationCoordinate2D
    let onDelete: () -> Void
    let onInsertAfter: () -> Void
    /// Non-nil when the device has a known location — shows a Menu instead of a plain button.
    let onInsertCurrentLocationAfter: (() -> Void)?

    var isLast: Bool { index == totalCount - 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline track
            VStack(spacing: 0) {
                Rectangle()
                    .fill(index == 0 ? Color.clear : Color.gray.opacity(0.3))
                    .frame(width: 2, height: 12)

                Circle()
                    .fill(dotColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))

                if !isLast {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 2)
                        insertButton
                    }
                    .frame(maxHeight: .infinity)
                    .frame(minHeight: 30)
                } else {
                    Spacer().frame(height: 12)
                }
            }
            .frame(width: 20)

            // Waypoint card
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pointTitle(for: index, total: totalCount))
                        .font(.system(size: 15, weight: .medium))
                    Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.systemBackground).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, isLast ? 0 : 4)
        }
        .padding(.horizontal, 16)
    }

    /// The inter-waypoint "+" insert button — plain or Menu depending on location availability.
    @ViewBuilder
    private var insertButton: some View {
        if let insertWithLocation = onInsertCurrentLocationAfter {
            Menu {
                Button(action: onInsertAfter) {
                    Label("Vybrat na mapě", systemImage: "map")
                }
                Button(action: insertWithLocation) {
                    Label("Použít aktuální polohu", systemImage: "location.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        } else {
            Button(action: onInsertAfter) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    private var dotColor: Color {
        index == 0 ? .green : (isLast ? .red : .blue)
    }

    private func pointTitle(for index: Int, total: Int) -> String {
        if index == 0 { return "Start" }
        if index == total - 1 { return "Cíl" }
        return "Průjezdní bod \(index)"
    }
}
