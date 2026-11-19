import Foundation
import VeloCore

struct Waypoint: Identifiable, Hashable, Codable {
    let id: UUID
    /// Position on the road network (the marker sits exactly on the road).
    var coordinate: GeoCoordinate
    var name: String?
    /// Cached snap result; not persisted because the bundled graph can change between versions.
    var networkPoint: NetworkPoint?

    init(id: UUID = UUID(), coordinate: GeoCoordinate, name: String? = nil, networkPoint: NetworkPoint? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.networkPoint = networkPoint
    }

    private enum CodingKeys: String, CodingKey { case id, coordinate, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coordinate = try c.decode(GeoCoordinate.self, forKey: .coordinate)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        networkPoint = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(coordinate, forKey: .coordinate)
        try c.encodeIfPresent(name, forKey: .name)
    }
}

enum WaypointRole: Hashable {
    case start
    case via(Int)
    case finish

    static func role(at index: Int, count: Int) -> WaypointRole {
        if index == 0 { return .start }
        if index == count - 1 { return .finish }
        return .via(index)
    }

    var title: String {
        switch self {
        case .start: return "Start"
        case .via(let n): return "Zastávka \(n)"
        case .finish: return "Cíl"
        }
    }
}

struct PlanSnapshot: Codable {
    var waypoints: [Waypoint]
    var options: RoutingOptions
}

enum MapStyleChoice: String, CaseIterable, Identifiable, Codable {
    case standard
    case hybrid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Mapa"
        case .hybrid: return "Satelit"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
}

/// Simple UserDefaults-backed persistence of the current plan and preferences.
enum PlanStorage {
    private static let planKey = "plan.current.v1"

    static func loadPlan() -> PlanSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: planKey) else { return nil }
        return try? JSONDecoder().decode(PlanSnapshot.self, from: data)
    }

    static func savePlan(_ plan: PlanSnapshot) {
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
    }
}
