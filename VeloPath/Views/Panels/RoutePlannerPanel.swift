//
//  RoutePlannerPanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 11.10.2025.
//

import SwiftUI
import CoreLocation

struct RoutePlannerPanel: View {
    @Binding var offset: CGFloat
    @GestureState private var dragOffset: CGFloat = 0

    @Binding var routePlan: RoutePlan
    @Binding var isPlacingWaypoint: Bool
    @Binding var insertionIndex: Int?
    @Binding var qualityBalance: Double

    // Panel sizing
    @State private var panelHeight: CGFloat = min(520, UIScreen.main.bounds.height * 0.55)
    private let handlePeek: CGFloat = 100
    private var closedOffset: CGFloat { panelHeight - handlePeek }

    var body: some View {
        let totalOffset = offset + dragOffset

        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        togglePanel()
                    }
                }

            // Panel content
            VStack(spacing: 12) {
                Text("Plánovač trasy")
                    .font(.headline)
                    .padding(.bottom, 4)

                if routePlan.points.isEmpty {
                    Text("Klepněte na mapu pro přidání startu a cíle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                // Show list with plus between items
                ForEach(0..<(max(1, routePlan.points.count)), id: \.self) { i in
                    HStack {
                        if i < routePlan.points.count {
                            let coord = routePlan.points[i]
                            Circle()
                                .fill(i == 0 ? Color.green : (i == routePlan.points.count - 1 ? .red : .blue))
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(i == 0 ? "Start" : (i == routePlan.points.count - 1 ? "Cíl" : "Průjezdní bod \(i)"))
                                    .font(.subheadline)
                                Text(format(coord: coord))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        // plus button between i and i+1
                        Button(action: {
                            // set insertion point to i+1, enter placement mode
                            insertionIndex = min(i + 1, routePlan.points.count)
                            isPlacingWaypoint = true
                        }) {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                Divider()

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
                .padding(.horizontal)

                Divider()

                Button {
                    NotificationCenter.default.post(name: .recalculateRoute, object: nil)
                } label: {
                    Label("Naplánovat trasu", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(routePlan.hasAtLeastStartAndEnd ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                .disabled(!routePlan.hasAtLeastStartAndEnd)

                Button {
                    NotificationCenter.default.post(name: .exportGPX, object: nil)
                } label: {
                    Label("Export do GPX", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
        .frame(maxWidth: .infinity, alignment: .center)
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
            if offset == 0 {
                offset = closedOffset
            }
        }
    }

    // MARK: - Actions
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

    private func format(coord: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
    }

}
