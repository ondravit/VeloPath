import Foundation

/// How strongly the router prefers good pavement over a shorter route.
public enum SurfacePriority: String, CaseIterable, Codable, Sendable, Hashable {
    /// Shortest sensible road-bike route; only avoids cobbles and gravel a little.
    case direct
    /// Default – accepts small detours for noticeably better roads.
    case balanced
    /// Takes detours to stay on the best roads.
    case best

    /// Weight of pavement quality in the cost function (0…1).
    public var qualityWeight: Double {
        switch self {
        case .direct: return 0
        case .balanced: return 0.5
        case .best: return 1
        }
    }
}

public struct RoutingOptions: Codable, Sendable, Hashable {
    public var surfacePriority: SurfacePriority
    /// Avoid class I roads (and trunks) and slightly avoid class II roads.
    public var avoidMainRoads: Bool

    public init(surfacePriority: SurfacePriority = .balanced, avoidMainRoads: Bool = false) {
        self.surfacePriority = surfacePriority
        self.avoidMainRoads = avoidMainRoads
    }
}

/// Per-attribute cost multipliers. Cost of a road = length × multiplier(attributes).
///
/// Mirrors `cost_table` in pipeline/velopath_pipeline/reference.py – keep both in sync,
/// the unit tests compare routes of the two implementations.
/// All multipliers are ≥ 1, which keeps the straight-line A* heuristic admissible.
public struct CostModel: Sendable {
    static let classFactor: [Double] = [1.0, 1.15, 1.08, 1.25, 1.2, 1.05, 1.0, 1.0, 1.06, 1.3, 1.6, 1.3, 1.3, 1.3, 1.3, 1.3]
    static let classFactorAvoidMain: [Int: Double] = [8: 1.25, 9: 2.5, 10: 4.0]
    static let surfaceK: [Double] = [0.0, 0.25, 0.4, 1.2, 2.5, 0.12, 2.0, 0.25]
    static let conditionK: [Double] = [0.0, 0.06, 0.25, 0.75, 1.6, 2.8, 0.25, 0.25]
    static let dismountFactor = 3.0

    public let options: RoutingOptions
    let table: [Double]

    public init(options: RoutingOptions) {
        self.options = options
        let q = min(1, max(0, options.surfacePriority.qualityWeight))
        var t = [Double](repeating: 1, count: 1 << 13)
        for code in 0..<(1 << 13) {
            let rc = code & 0xF
            let surface = (code >> 4) & 0x7
            let condition = (code >> 7) & 0x7
            let dismount = code & (1 << 12) != 0
            var f = CostModel.classFactor[rc]
            if options.avoidMainRoads, let avoid = CostModel.classFactorAvoidMain[rc] { f = avoid }
            f *= 1 + (0.3 + 0.7 * q) * CostModel.surfaceK[surface]
            f *= 1 + q * CostModel.conditionK[condition]
            if dismount { f *= CostModel.dismountFactor }
            t[code] = f
        }
        table = t
    }

    public func multiplier(_ attributes: EdgeAttributes) -> Double { table[attributes.costIndex] }
}
