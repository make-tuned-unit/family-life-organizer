import SwiftUI

@main
struct FamilyLifeApp: App {
    @State private var authService = AuthService()
    @State private var apiService = APIService()
    @State private var householdService = HouseholdService()
    @State private var profileImageCache = ProfileImageCache()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiService)
                .environment(householdService)
                .environment(profileImageCache)
                .task {
                    if authService.isAuthenticated {
                        await authService.validateSession(api: apiService)
                    }
                    if authService.isAuthenticated {
                        await householdService.reload(api: apiService, profileCache: profileImageCache)
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await householdService.reload(api: apiService, profileCache: profileImageCache)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: APIService.unauthorizedNotification)) { _ in
                    Task {
                        await authService.validateSession(api: apiService)
                    }
                }
                .preferredColorScheme(.light)
        }
    }
}
