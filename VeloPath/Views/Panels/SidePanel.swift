//
//  SidePanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 12.10.2025.
//

import SwiftUI

struct SidePanel: View {
    @Binding var roadDisplayMode: RoadDisplayMode
    @State private var showInfo = false

    var body: some View {
        // ⚙️ Floating action buttons
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // Info button
                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .padding(13)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .sheet(isPresented: $showInfo) {
                        InfoView()
                    }

                    // Layers button
                    Button {
                        cycleDisplayMode()
                    } label: {
                        Image(systemName: iconName(for: roadDisplayMode))
                            .font(.system(size: 18, weight: .medium))
                            .padding(13)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    // Location button
                    Button {
                        NotificationCenter.default.post(name: .recenterMap, object: nil)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .medium))
                            .padding(13)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 4)
                .padding(.top, 60)
            }
            Spacer()
        }
    }
    // MARK: - Helpers
    private func cycleDisplayMode() {
        let next = (roadDisplayMode.rawValue + 1) % RoadDisplayMode.allCases.count
        roadDisplayMode = RoadDisplayMode(rawValue: next)!
    }

    private func iconName(for mode: RoadDisplayMode) -> String {
        switch mode {
        case .none:
            return "square.3.layers.3d"
        case .knownOnly:
            return "square.3.layers.3d.middle.filled"
        case .all:
            return "square.3.layers.3d.top.filled"
        }
    }
}

private struct InfoView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        Image("VeloPath")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .shadow(radius: 10)
                        

                        Text("VeloPath")
                            .font(.title.bold())

                        Text("Cyklistická mapa kvality povrchu silnic.\nAplikace zobrazuje silnice podle jejich stavu povrchu, aby si cyklisté mohli plánovat bezpečnější a příjemnější trasy.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 12)

                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nápověda")
                                .font(.headline)
                                .padding(.bottom, 4)

                            LegendRow(color: Color(red: 0.0, green: 0.3, blue: 0.0), label: RoadSegment.RoadCondition.excellent.rawValue)
                            LegendRow(color: .green, label: RoadSegment.RoadCondition.good.rawValue)
                            LegendRow(color: .yellow, label: RoadSegment.RoadCondition.satisfactory.rawValue)
                            LegendRow(color: .orange, label: RoadSegment.RoadCondition.unsatisfactory.rawValue)
                            LegendRow(color: .red, label: RoadSegment.RoadCondition.emergency.rawValue)
                            LegendRow(color: .purple, label: RoadSegment.RoadCondition.superemergency.rawValue)
                            LegendRow(color: .gray, label: RoadSegment.RoadCondition.unknown.rawValue)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // Push footer to bottom when there's extra space
                        Spacer(minLength: 0)

                        // footer
                        VStack {
                            Divider()
                                .padding(.vertical, 8)

                            Text("© Ondřej Vít 2025")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .opacity(0.7)
                        }
                        .padding(.top, 12)
                    }
                    .padding()
                    // Make the scroll content at least as tall as the visible area
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
            .navigationTitle("O aplikaci")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Legend Row

private struct LegendRow: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(color)
                .frame(width: 40, height: 6)
                .cornerRadius(3)
            Text(label)
                .font(.subheadline)
        }
    }
}

enum RoadDisplayMode: Int, CaseIterable {
    case none        // nic se nevykreslí
    case knownOnly   // pouze známé silnice
    case all         // všechny (známé + neznámé)
}

