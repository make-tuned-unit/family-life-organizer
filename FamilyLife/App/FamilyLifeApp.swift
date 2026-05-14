import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var apiService: APIService?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 APNs device token: \(token)")
        guard let api = apiService else { return }
        Task {
            try? await api.registerDeviceToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

@main
struct FamilyLifeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                    // Wire up API service to app delegate for token registration
                    appDelegate.apiService = apiService

                    if authService.isAuthenticated {
                        await authService.validateSession(api: apiService)
                    }
                    if authService.isAuthenticated {
                        await householdService.reload(api: apiService, profileCache: profileImageCache, currentUserId: authService.currentUser?.id)
                        if let userId = authService.currentUser?.id {
                            messageCache.preload(api: apiService, userId: userId)
                        }
                        // Request permission + register for remote notifications
                        let granted = await NotificationService.shared.ensurePermissionIfNeeded()
                        if granted {
                            await MainActor.run {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                        }
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await householdService.reload(api: apiService, profileCache: profileImageCache, currentUserId: authService.currentUser?.id)
                            // Re-register for push on login
                            if await NotificationService.shared.isAuthorized() {
                                await MainActor.run {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
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
