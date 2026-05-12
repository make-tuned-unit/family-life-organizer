import SwiftUI

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
                    if authService.isAuthenticated {
                        await authService.validateSession(api: apiService)
                    }
                    if authService.isAuthenticated {
                        await householdService.reload(api: apiService)
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await householdService.reload(api: apiService)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: APIService.unauthorizedNotification)) { _ in
                    authService.logout()
                }
                .preferredColorScheme(.light)
        }
    }
}
