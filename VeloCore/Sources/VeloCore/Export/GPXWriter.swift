import Foundation

/// Serialises a route as GPX 1.1 (track with elevations + route waypoints).
///
/// The output is accepted by Garmin Connect, Wahoo, Hammerhead, Strava, Komoot, Mapy.com
/// and most other cycling tools.
public struct GPXWriter: Sendable {
    public struct Waypoint: Sendable {
        public var coordinate: GeoCoordinate
        public var name: String
        public init(coordinate: GeoCoordinate, name: String) {
            self.coordinate = coordinate
            self.name = name
        }
    }

    public var creator: String

    public init(creator: String = "VeloPath") {
        self.creator = creator
    }

    public func document(name: String, route: Route, waypoints: [Waypoint], date: Date = Date()) -> String {
        var out = ""
        out.reserveCapacity(route.points.count * 80 + 1024)
        out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"\(escape(creator))\" xmlns=\"http://www.topografix.com/GPX/1/1\" "
        out += "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
        out += "xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
        out += "  <metadata>\n"
        out += "    <name>\(escape(name))</name>\n"
        out += "    <time>\(Self.timestamp(date))</time>\n"
        out += "  </metadata>\n"
        for w in waypoints {
            out += "  <wpt lat=\"\(Self.coord(w.coordinate.latitude))\" lon=\"\(Self.coord(w.coordinate.longitude))\">\n"
            out += "    <name>\(escape(w.name))</name>\n"
            out += "  </wpt>\n"
        }
        out += "  <trk>\n"
        out += "    <name>\(escape(name))</name>\n"
        out += "    <type>cycling</type>\n"
        out += "    <trkseg>\n"
        var previous: GeoCoordinate?
        for (i, p) in route.points.enumerated() {
            if let prev = previous, prev == p { continue }
            previous = p
            out += "      <trkpt lat=\"\(Self.coord(p.latitude))\" lon=\"\(Self.coord(p.longitude))\">"
            if i < route.elevations.count, let e = route.elevations[i] {
                out += "<ele>\(Self.elevation(e))</ele>"
            }
            out += "</trkpt>\n"
        }
        out += "    </trkseg>\n"
        out += "  </trk>\n"
        out += "</gpx>\n"
        return out
    }

    public func data(name: String, route: Route, waypoints: [Waypoint], date: Date = Date()) -> Data {
        Data(document(name: name, route: route, waypoints: waypoints, date: date).utf8)
    }

    // MARK: - Formatting helpers (locale independent)

    static func coord(_ v: Double) -> String { String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), v) }
    static func elevation(_ v: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), v) }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    func escape(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "'": r += "&apos;"
            default: r.append(ch)
            }
        }
        return r
    }
}
