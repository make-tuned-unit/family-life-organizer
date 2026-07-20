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

    /// One-shot waiters for a single fresh fix (see `awaitFix`). Resolved by the
    /// delegate when a usable location arrives, or by a timeout with `nil`.
    @MainActor
    private final class FixWaiter {
        let continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>
        let startedAt: Date
        var isResumed = false
        init(continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>, startedAt: Date) {
            self.continuation = continuation
            self.startedAt = startedAt
        }
        func resume(with value: CLLocationCoordinate2D?) {
            guard !isResumed else { return }
            isResumed = true
            continuation.resume(returning: value)
        }
    }
    @MainActor private var fixWaiters: [FixWaiter] = []

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
        return await awaitFix(timeout: 10)
    }

    /// Read the current location WITHOUT ever prompting — returns nil unless
    /// permission was already granted. Used by the background presence report
    /// so the OS dialog can never appear from the poll loop.
    func currentLocationIfAuthorized() async -> CLLocationCoordinate2D? {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return nil
        }
        return await awaitFix(timeout: 10)
    }

    /// Request one fix and await the actual delegate callback (up to `timeout`),
    /// instead of blindly sleeping and returning whatever `currentLocation` holds
    /// — which was nil on a slow fix or a stale coordinate from an earlier
    /// tracking session. Returns the freshly-acquired coordinate, or nil on
    /// timeout. `deliverFix` only satisfies a waiter with a fix newer than the
    /// call start and of usable accuracy, so a stale coordinate is never handed back.
    @MainActor
    private func awaitFix(timeout: TimeInterval) async -> CLLocationCoordinate2D? {
        let start = Date()
        manager.requestLocation()
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            let waiter = FixWaiter(continuation: cont, startedAt: start)
            fixWaiters.append(waiter)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !waiter.isResumed else { return }
                fixWaiters.removeAll { $0 === waiter }
                waiter.resume(with: nil)
            }
        }
    }

    /// Resolve any pending one-shot waiters with a genuinely fresh, usable fix.
    /// A negative `horizontalAccuracy` marks an invalid fix; a fix older than the
    /// waiter's call start is a leftover from a previous session and is ignored
    /// (that waiter keeps waiting for a newer fix, or times out).
    @MainActor
    private func deliverFix(_ location: CLLocation) {
        guard !fixWaiters.isEmpty else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }
        let coord = location.coordinate
        var stillWaiting: [FixWaiter] = []
        for waiter in fixWaiters {
            if location.timestamp >= waiter.startedAt.addingTimeInterval(-5) {
                waiter.resume(with: coord)
            } else {
                stillWaiting.append(waiter)
            }
        }
        fixWaiters = stillWaiting
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.updateHandler?(location.coordinate)
            self.deliverFix(location)
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

    /// Enabling `allowsBackgroundLocationUpdates` throws a hard exception unless
    /// the bundle declares the "location" background mode in UIBackgroundModes.
    /// Gate on the bundle so a missing/misconfigured Info.plist degrades to
    /// foreground-only tracking instead of crashing the app.
    private static let declaresLocationBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()

    private func applyBackgroundMode() {
        let canBackground = manager.authorizationStatus == .authorizedAlways
            && Self.declaresLocationBackgroundMode
        manager.allowsBackgroundLocationUpdates = canBackground
        manager.showsBackgroundLocationIndicator = canBackground
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
