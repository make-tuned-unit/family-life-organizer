import SwiftUI
import SwiftData

@main
struct FamilyLifeApp: App {
    @State private var authService = AuthService()
    @State private var apiService = APIService()
    @State private var householdService = HouseholdService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiService)
                .environment(householdService)
                .task {
                    await authService.validateSession()
                    if authService.isAuthenticated {
                        await householdService.load(api: apiService)
                    }
                }
                .preferredColorScheme(.light)
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
