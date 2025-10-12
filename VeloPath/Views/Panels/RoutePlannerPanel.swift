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

    @State private var points: [String] = ["Start", "End"]
    @State private var locations: [String] = ["", ""]
    @State private var qualityBalance: Double = 0.5

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

                ForEach(Array(points.enumerated()), id: \.offset) { index, label in
                    HStack {
                        Circle()
                            .fill(index == 0 ? Color.green :
                                  (index == points.count - 1 ? .red : .blue))
                            .frame(width: 10, height: 10)

                        TextField(label, text: $locations[index])
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 4)

                        if points.count > 2 && index != 0 && index != points.count - 1 {
                            Button {
                                removePoint(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    addMidwayPoint()
                } label: {
                    Label("Přidat průjezdní bod", systemImage: "plus.circle.fill")
                        .font(.subheadline)
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
                    calculateRoute()
                } label: {
                    Label("Naplánovat trasu", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: max(totalOffset, 0)) // prevent dragging past top
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
    }

    // MARK: - Actions
    private func togglePanel() {
        offset = offset == 0 ? 305 : 0
    }

    private func endDrag(value: CGFloat) {
        if value > 100 {
            offset = 305 // collapse
        } else if value < -100 {
            offset = 0 // expand
        }
    }

    private func addMidwayPoint() {
        points.insert("Waypoint", at: points.count - 1)
        locations.insert("", at: locations.count - 1)
    }

    private func removePoint(at index: Int) {
        guard index > 0 && index < points.count - 1 else { return }
        points.remove(at: index)
        locations.remove(at: index)
    }

    private func calculateRoute() {
        print("🧭 Calculating route for \(points.count) points with balance \(qualityBalance)")
    }
}
