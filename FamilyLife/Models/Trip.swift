import Foundation
import SwiftData

@Model
final class Trip {
    var serverId: Int?
    var traveler: String
    var origin: String?
    var originLat: Double?
    var originLng: Double?
    var destination: String
    var destinationLat: Double?
    var destinationLng: Double?
    var purpose: String?
    var status: String
    var currentLat: Double?
    var currentLng: Double?
    var etaMinutes: Int?
    var startedAt: Date
    var arrivedAt: Date?

    init(
        serverId: Int? = nil,
        traveler: String,
        destination: String,
        status: String = "active"
    ) {
        self.serverId = serverId
        self.traveler = traveler
        self.destination = destination
        self.status = status
        self.startedAt = Date()
    }
}

struct TripResponse: Codable, Identifiable {
    var id: Int
    var traveler: String
    var origin: String?
    var origin_lat: Double?
    var origin_lng: Double?
    var destination: String
    var destination_lat: Double?
    var destination_lng: Double?
    var purpose: String?
    var status: String
    var current_lat: Double?
    var current_lng: Double?
    var eta_minutes: Int?
    var started_at: String?
    var arrived_at: String?
    var created_at: String?
}

struct FamilyAddressResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let radius_meters: Int?
    let created_by: String?
}
