import CoreLocation
import Foundation
import VeloCore

/// Reverse geocoding of waypoint names. Requests are serialised because CLGeocoder
/// allows only one request at a time and is rate limited.
@MainActor
final class GeocodingService {
    private let geocoder = CLGeocoder()
    private var queue: [(GeoCoordinate, (String?) -> Void)] = []
    private var isRunning = false
    private var cache: [String: String] = [:]

    func name(for coordinate: GeoCoordinate, completion: @escaping (String?) -> Void) {
        let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        if let hit = cache[key] {
            completion(hit)
            return
        }
        queue.append((coordinate, { [weak self] name in
            if let name { self?.cache[key] = name }
            completion(name)
        }))
        runNext()
    }

    private func runNext() {
        guard !isRunning, !queue.isEmpty else { return }
        isRunning = true
        let (coordinate, completion) = queue.removeFirst()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task { @MainActor in
            var result: String?
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "cs_CZ"))
                if let p = placemarks.first { result = Self.format(p) }
            } catch {
                result = nil
            }
            completion(result)
            isRunning = false
            runNext()
        }
    }

    private static func format(_ p: CLPlacemark) -> String? {
        let place = p.locality ?? p.subLocality ?? p.subAdministrativeArea
        let street = p.thoroughfare
        switch (street, place) {
        case let (s?, l?) where s != l: return "\(s), \(l)"
        case let (_, l?): return l
        case let (s?, nil): return s
        default: return p.name
        }
    }
}
