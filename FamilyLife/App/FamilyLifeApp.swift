import SwiftUI

@main
struct FamilyLifeApp: App {
    @State private var authService = AuthService()
    @State private var apiService = APIService()
    @State private var householdService = HouseholdService()
    @State private var profileImageCache = ProfileImageCache()
    @State private var messageCache = MessageCache()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiService)
                .environment(householdService)
                .environment(profileImageCache)
                .environment(messageCache)
                .task {
                    if authService.isAuthenticated {
                        await authService.validateSession(api: apiService)
                    }
                    if authService.isAuthenticated {
                        await householdService.reload(api: apiService, profileCache: profileImageCache, currentUserId: authService.currentUser?.id)
                        if let userId = authService.currentUser?.id {
                            messageCache.preload(api: apiService, userId: userId)
                        }
                        // Request notification permission on first authenticated launch
                        _ = await NotificationService.shared.ensurePermissionIfNeeded()
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await householdService.reload(api: apiService, profileCache: profileImageCache, currentUserId: authService.currentUser?.id)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: APIService.unauthorizedNotification)) { _ in
                    Task {
                        await authService.validateSession(api: apiService)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    guard authService.isAuthenticated, let userId = authService.currentUser?.id else { return }
                    messageCache.preload(api: apiService, userId: userId)
                }
                .preferredColorScheme(.light)
        }
    }
}
