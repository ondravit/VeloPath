//
//  RoutePlannerPanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 11.10.2025.
//

import SwiftUI
import CoreLocation

struct RoutePlannerPanel: View {
    
    // MARK: - Bindings
    @Binding var offset: CGFloat
    @GestureState private var dragOffset: CGFloat = 0

    @Binding var routePlan: RoutePlan
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    @Binding var qualityBalance: Double
    let routeDistance: Double

    // MARK: - Configuration: Panel Sizing
    
    // Fixed height based on screen percentage to ensure consistency between empty/populated states
    private let panelHeight: CGFloat = UIScreen.main.bounds.height * 0.60
    
    // The amount of the panel visible when collapsed (Handle + Title)
    private let handlePeek: CGFloat = 120
    
    // Calculated offset for the closed state
    private var closedOffset: CGFloat { panelHeight - handlePeek }

    // MARK: - Body
    var body: some View {
        let totalOffset = offset + dragOffset

        VStack(spacing: 0) {
            
            // 1. Drag Handle
            // Increased touch area with transparent background for easier interaction
            VStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    togglePanel()
                }
            }

            // 2. Panel Content
            VStack(spacing: 0) {
                Text("Plánovač trasy")
                    .font(.headline)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                
                if routeDistance > 0 {
                    Text(formatDistance(routeDistance))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.bottom, 15)
                } else {
                    Color.clear.frame(height: 10).padding(.bottom, 10)
                }

                ZStack {
                    if routePlan.points.isEmpty {
                        emptyStateView
                    } else {
                        // Timeline Style List
                        List {
                            ForEach(0..<routePlan.points.count, id: \.self) { i in
                                TimelineRow(
                                    index: i,
                                    totalCount: routePlan.points.count,
                                    coord: routePlan.points[i],
                                    onDelete: {
                                        withAnimation {
                                            if routePlan.points.indices.contains(i) {
                                                routePlan.points.remove(at: i)
                                            }
                                        }
                                    },
                                    onInsertAfter: {
                                        insertionIndex = i + 1
                                        isPlacingWaypoint = true
                                    }
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                            .onMove { indices, newOffset in
                                routePlan.points.move(fromOffsets: indices, toOffset: newOffset)
                            }
                            
                            appendButton
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        }
                        .listStyle(.plain)
                        // Fixed height for the list area to allow space for bottom controls
                        .frame(height: 240)
                    }
                }
                .frame(maxHeight: .infinity)

                // Separator
                Divider()
                    .padding(.top, 8)

                // Slider Section
                qualitySliderSection
                    .padding()

                // Separator
                Divider()

                // Bottom Action Buttons
                bottomButtons
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 30) // Lifted up from the bottom edge
            }
        }
        // Apply fixed dimensions to the entire panel container
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -2)
        .offset(y: max(0, min(totalOffset, closedOffset)))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        endDrag(value: value.translation.height)
                    }
                }
        )
        .onAppear {
            // Set initial position to closed
            if offset == 0 { offset = closedOffset }
        }
    }

    // MARK: - Subviews & Components
    
    // View shown when no points are selected
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Klepněte na mapu pro přidání\nstartu a cíle")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // Component: Single Row in the Timeline List
    struct TimelineRow: View {
        let index: Int
        let totalCount: Int
        let coord: CLLocationCoordinate2D
        let onDelete: () -> Void
        let onInsertAfter: () -> Void
        
        var isLast: Bool { index == totalCount - 1 }
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                // Left Column: Timeline Visuals (Line + Dot)
                VStack(spacing: 0) {
                    // Top line connector
                    Rectangle()
                        .fill(index == 0 ? Color.clear : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 12)
                    
                    // Waypoint Dot
                    Circle()
                        .fill(index == 0 ? Color.green : (isLast ? Color.red : Color.blue))
                        .frame(width: 14, height: 14)
                        .background(Circle().stroke(Color.white, lineWidth: 2))
                    
                    // Bottom line connector with "Insert" button
                    if !isLast {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2)
                            
                            // Small Plus Button on the line
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
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 30)
                    } else {
                        Spacer().frame(height: 12)
                    }
                }
                .frame(width: 20)
                
                // Right Column: Content (Text + Delete)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pointTitle(for: index, total: totalCount))
                                .font(.system(size: 15, weight: .medium))
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Drag Handle Icon
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary.opacity(0.4))
                        
                        // Delete Button
                        Button(action: onDelete) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(6)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.systemBackground).opacity(0.6))
                    .cornerRadius(10)
                    .padding(.bottom, isLast ? 0 : 4)
                }
            }
        }
        
        // Helper to determine the title of the point based on index
        private func pointTitle(for index: Int, total: Int) -> String {
            if index == 0 { return "Start" }
            if index == total - 1 { return "Cíl" }
            return "Průjezdní bod \(index)"
        }
    }
    
    // Component: Button to append a new waypoint at the end
    private var appendButton: some View {
        HStack {
            // Visual alignment line
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 2, height: 20)
                .padding(.leading, 9)
                .padding(.trailing, 21)
            
            Button(action: {
                insertionIndex = routePlan.points.count
                isPlacingWaypoint = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Přidat zastávku")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.top, -8)
    }
    
    // Component: Quality/Distance Slider
    private var qualitySliderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Nejkratší")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Nejkvalitnější")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Slider(value: $qualityBalance, in: 0...1)
                .tint(.blue)

            Text("Poměr: \(Int(qualityBalance * 100)) % kvalita")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // Component: Bottom Action Buttons
    private var bottomButtons: some View {
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(name: .recalculateRoute, object: nil)
            } label: {
                Label("Přepočítat trasu", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(routePlan.hasAtLeastStartAndEnd ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!routePlan.hasAtLeastStartAndEnd)
            
            Button {
                NotificationCenter.default.post(name: .exportGPX, object: nil)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Helpers & Logic
    
    private func togglePanel() {
        offset = offset == 0 ? closedOffset : 0
    }

    private func endDrag(value: CGFloat) {
        if value > 100 {
            offset = closedOffset
        } else if value < -100 {
            offset = 0
        } else {
            let proposed = offset + value
            offset = proposed > (closedOffset / 2) ? closedOffset : 0
        }
    }
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}
