import SwiftUI
import SwiftData

@main
struct FamilyLifeApp: App {
    @State private var authService = AuthService()
    @State private var apiService = APIService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiService)
                .task { await authService.validateSession() }
        }
        .modelContainer(for: [
            FLTask.self,
            Grocery.self,
            Appointment.self,
            Receipt.self,
            BudgetCategory.self,
            PantryItem.self,
            Trip.self,
            Rivalry.self,
            RivalryEntry.self,
            FamilyMemberPoints.self,
            Decision.self,
            DecisionReaction.self,
            DecisionComment.self,
            GiftPerson.self,
            GiftIdea.self,
            SpecialEvent.self
        ])
    }
}
