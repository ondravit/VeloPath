import GRDB

/// A directed graph edge loaded from the `edges` table.
/// `condition` is an integer 0-6 matching the RoadCondition encoding written by VeloGraphBuilder.
struct DBEdge: FetchableRecord, Decodable, Sendable {
    let id: Int64
    let fromNode: Int64
    let toNode: Int64
    let distanceM: Double
    let condition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case fromNode  = "from_node"
        case toNode    = "to_node"
        case distanceM = "distance_m"
        case condition
    }

    /// Weighted cost used by the routing algorithm.
    /// Mirrors `RoadGraph.defaultMultiplier` from the old GeoJSON path.
    var cost: Double {
        distanceM * DBEdge.conditionMultiplier(condition)
    }

    static func conditionMultiplier(_ c: Int) -> Double {
        switch c {
        case 0:  return 1.00  // excellent
        case 1:  return 1.10  // good
        case 2:  return 1.20  // satisfactory
        case 3:  return 1.45  // unsatisfactory
        case 4:  return 1.90  // emergency
        case 5:  return 2.50  // superemergency
        default: return 2.00  // unknown
        }
    }
}
