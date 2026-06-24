import Foundation
import CoreLocation
import MapKit
import UIKit

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isTracking = false

    /// True when the user has granted "Always" location permission
    var hasAlwaysPermission: Bool { authorizationStatus == .authorizedAlways }

    /// True when the user has "When In Use" but hasn't yet been asked for "Always"
    var canRequestAlways: Bool { authorizationStatus == .authorizedWhenInUse }

    /// True when the user explicitly denied location or restricted
    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    private let manager = CLLocationManager()
    private var updateHandler: ((CLLocationCoordinate2D) -> Void)?
    private var wantsTripTrackingPermission = false
    private var arrivalHandler: (() -> Void)?
    private var monitoredTripRegionId: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_AUTOLOGIN"] != nil { return }
        #endif
        manager.requestWhenInUseAuthorization()
    }

    func requestTripTrackingPermission() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_AUTOLOGIN"] != nil { return }
        #endif
        wantsTripTrackingPermission = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Open the app's Settings page so the user can grant "Always" permission
    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func startTracking(onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        updateHandler = onUpdate
        isTracking = true
        applyBackgroundMode()
        manager.startUpdatingLocation()
        // Significant location changes survive app termination — acts as a safety net
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopTracking() {
        isTracking = false
        updateHandler = nil
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        clearArrivalGeofence()
    }

    /// Monitor a geofence around the trip destination; fires `onArrival` when entered
    func monitorArrival(tripId: Int, destination: CLLocationCoordinate2D, radiusMeters: Double = 150, onArrival: @escaping () -> Void) {
        clearArrivalGeofence()
        arrivalHandler = onArrival
        let regionId = "trip-arrive-\(tripId)"
        monitoredTripRegionId = regionId
        let region = CLCircularRegion(center: destination, radius: radiusMeters, identifier: regionId)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func clearArrivalGeofence() {
        if let regionId = monitoredTripRegionId {
            for region in manager.monitoredRegions where region.identifier == regionId {
                manager.stopMonitoring(for: region)
            }
            monitoredTripRegionId = nil
        }
        arrivalHandler = nil
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        requestPermission()
        manager.requestLocation()
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

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("trip-arrive-") else { return }
        Task { @MainActor in
            self.arrivalHandler?()
            self.clearArrivalGeofence()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            // Two-step "Always" flow: after "When In Use" is granted, request "Always"
            if self.wantsTripTrackingPermission,
               manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }

            // If we're already tracking and auth upgraded to "Always", enable background mode
            if self.isTracking {
                self.applyBackgroundMode()
            }
        }
    }

    // MARK: - Private

    private func applyBackgroundMode() {
        let isAlways = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = isAlways
        manager.showsBackgroundLocationIndicator = isAlways
    }

    // MARK: - Distance helpers

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc)
    }

    static func etaMinutes(distanceMeters: Double, speedMps: Double = 16.0) -> Int {
        guard speedMps > 0 else { return 0 }
        return Int(distanceMeters / speedMps / 60.0)
    }

    static func routeEtaMinutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Int? {
        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))

        do {
            let response = try await MKDirections(request: request).calculateETA()
            return max(0, Int(response.expectedTravelTime / 60.0))
        } catch {
            return nil
        }
    }
}
