import CoreLocation

/// A road segment used for map rendering.
/// `coords` is populated by `DatabaseService.fetchSegments(in:)` from `segment_coords`.
struct DBSegment: Identifiable, Sendable {
    let id: Int64
    let condition: Int
    var coords: [CLLocationCoordinate2D]

    init(id: Int64, condition: Int, coords: [CLLocationCoordinate2D] = []) {
        self.id = id
        self.condition = condition
        self.coords = coords
    }
}
