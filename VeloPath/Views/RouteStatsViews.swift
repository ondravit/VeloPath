import Charts
import SwiftUI
import VeloCore

/// Thin stacked bar showing the share of each pavement condition on the route.
struct QualityBar: View {
    let breakdown: [RoadCondition: Double]
    let total: Double

    private var order: [RoadCondition] { RoadCondition.known + [.unknown] }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(order, id: \.self) { c in
                    let share = total > 0 ? (breakdown[c] ?? 0) / total : 0
                    if share > 0.002 {
                        Rectangle()
                            .fill(c.color)
                            .frame(width: max(2, geo.size.width * share - 1.5))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        order.compactMap { c -> String? in
            let m = breakdown[c] ?? 0
            guard m > 0, total > 0 else { return nil }
            return "\(c.title) \(Format.percent(m / total))"
        }.joined(separator: ", ")
    }
}

private struct SurfaceShare: Identifiable {
    let surface: Surface
    let meters: Double
    var id: Surface { surface }
}

struct QualityBreakdownView: View {
    let route: Route

    var body: some View {
        let breakdown = route.conditionBreakdown
        let surfaces = route.surfaceBreakdown
            .filter { $0.key.isNoteworthy && $0.value >= 50 }
            .map { SurfaceShare(surface: $0.key, meters: $0.value) }
            .sorted { $0.meters > $1.meters }
        VStack(alignment: .leading, spacing: 12) {
            QualityBar(breakdown: breakdown, total: route.distance)
                .frame(height: 10)
            ForEach(RoadCondition.known + [.unknown], id: \.self) { c in
                if let m = breakdown[c], m >= 10 {
                    HStack {
                        Circle().fill(c.color).frame(width: 10, height: 10)
                        Text(c == .unknown ? "Stav neznámý" : c.title)
                        Spacer()
                        Text(Format.distance(m)).monospacedDigit()
                        Text(Format.percent(m / max(route.distance, 1)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
            if !surfaces.isEmpty {
                Divider()
                ForEach(surfaces) { share in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(share.surface.title)
                        Spacer()
                        Text(Format.distance(share.meters)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            roadClassSummary
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var roadClassSummary: some View {
        let classes = route.roadClassBreakdown
        let main = (classes[.primary] ?? 0) + (classes[.trunk] ?? 0)
        if main >= 100 {
            HStack {
                Image(systemName: "car.fill").foregroundStyle(.secondary).font(.caption)
                Text("Silnice I. třídy")
                Spacer()
                Text(Format.distance(main)).monospacedDigit()
            }
            .font(.subheadline)
        }
    }
}

struct ElevationChartView: View {
    let route: Route

    var body: some View {
        let samples = route.elevationProfile(maxSamples: 200)
        if samples.count < 2 {
            Text("Výškový profil není k dispozici.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            let minE = samples.map(\.elevation).min() ?? 0
            let maxE = samples.map(\.elevation).max() ?? 0
            let pad = max(10, (maxE - minE) * 0.15)
            let lower = (minE - pad).rounded(.down)
            let upper = (maxE + pad).rounded(.up)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Label(Format.elevation(route.ascent), systemImage: "arrow.up.right")
                    Label(Format.elevation(route.descent), systemImage: "arrow.down.right")
                    Spacer()
                    Text("\(Format.elevation(minE)) – \(Format.elevation(maxE)) n. m.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .labelStyle(CompactLabelStyle())
                Chart(samples, id: \.distance) { s in
                    AreaMark(x: .value("Vzdálenost", s.distance / 1000),
                             yStart: .value("Základ", lower),
                             yEnd: .value("Výška", s.elevation))
                        .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Vzdálenost", s.distance / 1000),
                             y: .value("Výška", s.elevation))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: lower...upper)
                .chartXScale(domain: 0...(route.distance / 1000))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) { Text("\(Int(km.rounded())) km") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = value.as(Double.self) { Text("\(Int(m))") }
                        }
                    }
                }
            }
        }
    }
}
