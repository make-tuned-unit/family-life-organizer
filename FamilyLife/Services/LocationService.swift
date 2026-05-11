import Foundation
import CoreLocation
import MapKit

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isTracking = false

    private let manager = CLLocationManager()
    private var updateHandler: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking(onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        updateHandler = onUpdate
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        updateHandler = nil
        manager.stopUpdatingLocation()
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        requestPermission()
        manager.requestLocation()
        // Wait briefly for location
        try? await Task.sleep(for: .seconds(2))
        return currentLocation
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        Task { @MainActor in
            self.currentLocation = coord
            self.updateHandler?(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors are expected when permission not granted
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    // MARK: - Distance helpers

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc)
    }

    static func etaMinutes(distanceMeters: Double, speedMps: Double = 16.0) -> Int {
        // Default ~60 km/h driving speed
        guard speedMps > 0 else { return 0 }
        return Int(distanceMeters / speedMps / 60.0)
    }
}
