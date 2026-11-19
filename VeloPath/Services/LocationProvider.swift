import CoreLocation
import Foundation
import Observation
import VeloCore

/// Thin wrapper around CLLocationManager for "when in use" authorisation and one-shot fixes.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastLocation: GeoCoordinate?
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var pending: [(GeoCoordinate?) -> Void] = []

    override init() {
        let m = CLLocationManager()
        manager = m
        authorization = m.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks for permission if needed and delivers the current position (or nil).
    func requestCurrentLocation(_ completion: @escaping (GeoCoordinate?) -> Void) {
        if isDenied {
            completion(nil)
            return
        }
        pending.append(completion)
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    func requestAuthorizationIfNeeded() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    private func deliver(_ value: GeoCoordinate?) {
        let callbacks = pending
        pending.removeAll()
        callbacks.forEach { $0(value) }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized, !self.pending.isEmpty {
                self.manager.requestLocation()
            } else if self.isDenied {
                self.deliver(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let value = GeoCoordinate(latitude: c.latitude, longitude: c.longitude)
        Task { @MainActor in
            self.lastLocation = value
            self.deliver(value)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.deliver(nil) }
    }
}
