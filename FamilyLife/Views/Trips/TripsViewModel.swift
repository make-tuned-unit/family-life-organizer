import Foundation

@MainActor
@Observable
final class TripsViewModel {
    var activeTrip: TripResponse?
    var pastTrips: [TripResponse] = []
    var isLoading = false
    var error: String?

    private var lastLocationSyncAt: Date?

    func loadAll(api: APIService) async {
        isLoading = true
        error = nil
        do {
            let allTrips = try await api.fetchTrips()
            activeTrip = allTrips.first { $0.status == "active" }
            pastTrips = allTrips.filter { $0.status != "active" }
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startTrip(_ data: [String: Any], api: APIService) async {
        do {
            try await api.createTrip(data)
            if let traveler = data["traveler"] as? String,
               let dest = data["destination"] as? String,
               await NotificationService.shared.ensurePermissionIfNeeded() {
                NotificationService.shared.notifyTripStarted(traveler: traveler, destination: dest)
            }
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func arriveTrip(_ id: Int, api: APIService) async {
        do {
            try await api.arriveTrip(id: id)
            if let trip = activeTrip {
                NotificationService.shared.notifyTripArrival(traveler: trip.traveler, destination: trip.destination)
            }
            NotificationService.shared.clearTripAlertState(tripId: id)
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func cancelTrip(_ id: Int, api: APIService) async {
        do {
            try await api.cancelTrip(id: id)
            NotificationService.shared.clearTripAlertState(tripId: id)
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func deleteTrip(_ id: Int, api: APIService) async {
        do {
            try await api.deleteTrip(id: id)
            NotificationService.shared.clearTripAlertState(tripId: id)
            await loadAll(api: api)
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func updateLocation(tripId: Int, lat: Double, lng: Double, etaMinutes: Int, api: APIService) async {
        guard shouldSyncLocation(lat: lat, lng: lng, etaMinutes: etaMinutes) else { return }
        do {
            try await api.updateTrip(id: tripId, updates: [
                "current_lat": lat,
                "current_lng": lng,
                "eta_minutes": etaMinutes
            ])
            if var trip = activeTrip, trip.id == tripId {
                trip.current_lat = lat
                trip.current_lng = lng
                trip.eta_minutes = etaMinutes
                activeTrip = trip
            }
            lastLocationSyncAt = Date()
        } catch {
            guard !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }

    func maybeNotifyETA(for trip: TripResponse, etaMinutes: Int) async {
        guard await NotificationService.shared.isAuthorized() else { return }

        if etaMinutes <= 15, NotificationService.shared.shouldSendTripETAAlert(tripId: trip.id, minutes: 15) {
            NotificationService.shared.notifyTripETA(traveler: trip.traveler.capitalized, minutes: 15)
            NotificationService.shared.markTripETAAlertSent(tripId: trip.id, minutes: 15)
        }

        if etaMinutes <= 5, NotificationService.shared.shouldSendTripETAAlert(tripId: trip.id, minutes: 5) {
            NotificationService.shared.notifyTripETA(traveler: trip.traveler.capitalized, minutes: 5)
            NotificationService.shared.markTripETAAlertSent(tripId: trip.id, minutes: 5)
        }
    }

    private func shouldSyncLocation(lat: Double, lng: Double, etaMinutes: Int) -> Bool {
        guard let lastLocationSyncAt else { return true }
        if Date().timeIntervalSince(lastLocationSyncAt) > 15 {
            return true
        }
        if let activeTrip, activeTrip.eta_minutes != etaMinutes {
            return true
        }
        if let activeTrip,
           let currentLat = activeTrip.current_lat,
           let currentLng = activeTrip.current_lng {
            let movedMeters = LocationService.distance(
                from: .init(latitude: currentLat, longitude: currentLng),
                to: .init(latitude: lat, longitude: lng)
            )
            return movedMeters >= 50
        }
        return false
    }
}
