import CoreLocation
import GRDB

/// A graph node loaded from the `nodes` table.
struct DBNode: FetchableRecord, Decodable, Equatable, Sendable {
    let id: Int64
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
