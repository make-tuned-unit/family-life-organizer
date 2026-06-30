import SwiftUI
import UIKit
import CoreLocation

@Observable
class DeepLinkRouter {
    var pendingType: String?
    var pendingRefId: Int?
    var pendingName: String?

    func route(type: String, refId: Int?, name: String? = nil) {
        pendingType = type
        pendingRefId = refId
        pendingName = name
    }

    func consume() {
        pendingType = nil
        pendingRefId = nil
        pendingName = nil
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var apiService: APIService?
    var deepLinkRouter: DeepLinkRouter?

    var launchedForLocation = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Detect if app was launched by a significant location change (trip tracking)
        if launchOptions?[.location] != nil {
            launchedForLocation = true
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let api = apiService else { return }
        Task {
            try? await api.registerDeviceToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let type = userInfo["type"] as? String else { return }
        let refId = userInfo["ref_id"] as? Int
        let name = userInfo["name"] as? String
        await MainActor.run {
            deepLinkRouter?.route(type: type, refId: refId, name: name)
        }
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
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var locationService = LocationService()
    @State private var subscriptionService = SubscriptionService()
    @State private var conciergeLaunch = ConciergeLaunch()
    @State private var calendarService = CalendarService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiService)
                .environment(householdService)
                .environment(profileImageCache)
                .environment(messageCache)
                .environment(deepLinkRouter)
                .environment(locationService)
                .environment(subscriptionService)
                .environment(conciergeLaunch)
                .environment(calendarService)
                .task {
                    // Wire up API service and deep link router to app delegate
                    appDelegate.apiService = apiService
                    appDelegate.deepLinkRouter = deepLinkRouter

                    if authService.isAuthenticated {
                        await authService.validateSession(api: apiService)
                    }
                    if authService.isAuthenticated {
                        subscriptionService.start(api: apiService)
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
                        subscriptionService.start(api: apiService)
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
