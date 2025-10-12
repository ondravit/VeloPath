//
//  SidePanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 12.10.2025.
//

import SwiftUI

struct SidePanel: View {
    @State private var showInfo = false

    var body: some View {
        // ⚙️ Floating action buttons
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .sheet(isPresented: $showInfo) {
                        InfoView()
                    }

                    Button {
                        // TODO: hide road segments
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.title2)
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        // TODO: find location
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 80)
            }
            Spacer()
        }
    }
}

private struct InfoView: View {
    var body: some View {
        NavigationStack {
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
                }
                .padding()
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
