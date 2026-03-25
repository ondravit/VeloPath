import Foundation

// ─── Public types ────────────────────────────────────────────────────────────

/// One road condition value, stored as a raw Int32 that matches the iOS app's
/// RoadCondition enum and the INTEGER column in the SQLite `condition` field.
enum RoadCondition: Int32, CaseIterable {
    case excellent      = 0
    case good           = 1
    case satisfactory   = 2
    case unsatisfactory = 3
    case emergency      = 4
    case superemergency = 5
    case unknown        = 6

    /// Mirrors GeoJSONService.propertiesAsCondition() exactly, including
    /// the diacritic-insensitive folding used in the iOS app.
    static func from(stavSil raw: String?) -> RoadCondition {
        guard let raw else { return .unknown }
        let normalised = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        switch normalised {
        case "vyborny":        return .excellent
        case "dobry":          return .good
        case "vyhovujici":     return .satisfactory
        case "nevyhovujici":   return .unsatisfactory
        case "havarijni":      return .emergency
        case "superhavarijni": return .superemergency
        default:               return .unknown
        }
    }
}

/// A single GeoJSON feature decoded into Swift-native types.
/// Each feature can carry multiple polylines (MultiLineString → N polylines).
struct ParsedFeature {
    /// Each inner array is one polyline: ordered (lat, lon) pairs.
    /// Note: GeoJSON stores [longitude, latitude]; we swap here at parse time.
    let polylines: [[(lat: Double, lon: Double)]]
    let condition: RoadCondition
}

// ─── Parser ──────────────────────────────────────────────────────────────────

final class GeoJSONParser {

    /// Reads and fully parses a GeoJSON FeatureCollection from `path`.
    /// Handles LineString and MultiLineString geometries.
    func parse(path: String) throws -> [ParsedFeature] {
        let url = URL(fileURLWithPath: path)

        print("      Reading file…")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        print("      Deserialising JSON (\(String(format: "%.1f", Double(data.count) / 1_048_576)) MB)…")

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawFeatures = root["features"] as? [[String: Any]]
        else {
            throw ParserError.invalidFormat("Root object must be a GeoJSON FeatureCollection")
        }

        var result: [ParsedFeature] = []
        result.reserveCapacity(rawFeatures.count)

        var skipped = 0

        for raw in rawFeatures {
            guard
                let geometry = raw["geometry"] as? [String: Any],
                let geomType = geometry["type"] as? String
            else { skipped += 1; continue }

            let props     = raw["properties"] as? [String: Any]
            let stavSil   = props?["stav_sil"] as? String
            let condition = RoadCondition.from(stavSil: stavSil)

            var polylines: [[(lat: Double, lon: Double)]] = []

            switch geomType {
            case "LineString":
                if let coords = geometry["coordinates"] as? [[Any]],
                   let line = extractLine(from: coords) {
                    polylines.append(line)
                }

            case "MultiLineString":
                if let multiCoords = geometry["coordinates"] as? [[[Any]]] {
                    for coords in multiCoords {
                        if let line = extractLine(from: coords) {
                            polylines.append(line)
                        }
                    }
                }

            default:
                skipped += 1
                continue
            }

            guard !polylines.isEmpty else { skipped += 1; continue }
            result.append(ParsedFeature(polylines: polylines, condition: condition))
        }

        if skipped > 0 {
            print("      ⚠️  Skipped \(skipped) features (unsupported geometry or missing data)")
        }

        let conditionBreakdown = Dictionary(
            grouping: result, by: \.condition
        ).mapValues(\.count).sorted(by: { $0.key.rawValue < $1.key.rawValue })

        print("      Condition breakdown:")
        for (cond, count) in conditionBreakdown {
            print("        \(conditionName(cond)): \(count)")
        }

        return result
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// Converts a raw JSON coordinate array `[[lon, lat], …]` to `[(lat, lon)]`.
    /// GeoJSON stores longitude first per RFC 7946 §3.1.1.
    private func extractLine(from rawCoords: [[Any]]) -> [(lat: Double, lon: Double)]? {
        guard rawCoords.count >= 2 else { return nil }
        let points: [(lat: Double, lon: Double)] = rawCoords.compactMap { pair in
            // Each pair is [lon, lat] and possibly [lon, lat, elevation]
            guard
                pair.count >= 2,
                let lon = (pair[0] as? Double) ?? (pair[0] as? NSNumber).map(\.doubleValue),
                let lat = (pair[1] as? Double) ?? (pair[1] as? NSNumber).map(\.doubleValue)
            else { return nil }
            return (lat: lat, lon: lon)
        }
        return points.count >= 2 ? points : nil
    }

    private func conditionName(_ c: RoadCondition) -> String {
        switch c {
        case .excellent:      return "excellent     "
        case .good:           return "good          "
        case .satisfactory:   return "satisfactory  "
        case .unsatisfactory: return "unsatisfactory"
        case .emergency:      return "emergency     "
        case .superemergency: return "superemergency"
        case .unknown:        return "unknown       "
        }
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

enum ParserError: Error, CustomStringConvertible {
    case invalidFormat(String)

    var description: String {
        switch self {
        case .invalidFormat(let msg): return "GeoJSON parse error: \(msg)"
        }
    }
}
