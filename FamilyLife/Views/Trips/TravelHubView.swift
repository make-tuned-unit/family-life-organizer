import SwiftUI

/// Consolidates the three location/travel screens (Trips, Itineraries, saved
/// Places) behind one segmented toggle — mirrors the Budget tab pattern to keep
/// the More page uncluttered.
struct TravelHubView: View {
    @State private var segment: Segment = .trips

    enum Segment: String, CaseIterable, Identifiable {
        case trips = "Trips", itineraries = "Itineraries", places = "Places"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Travel", selection: $segment.animation(.easeInOut(duration: 0.2))) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
            .padding(.top, 10)
            .padding(.bottom, 6)

            switch segment {
            case .trips: TripsView()
            case .itineraries: ItineraryListView()
            case .places: FamilyAddressesView()
            }
        }
        .background { AmbientBackground(style: .home) }
        .navigationTitle("Travel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}
