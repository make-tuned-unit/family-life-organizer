import Foundation

/// Centralized app configuration for production deployment.
/// Change `environment` to `.production` before App Store submission.
enum AppConfig {
    enum Environment {
        case development
        case production
    }

    // MARK: - Active Environment
    // Toggle this for release builds
    #if DEBUG
    static let environment: Environment = .development
    #else
    static let environment: Environment = .production
    #endif

    // MARK: - API

    static var apiBaseURL: String {
        switch environment {
        case .development:
            // Local network — set your dev machine's IP here
            return UserDefaults.standard.string(forKey: "api_base_url")
                ?? "http://localhost:3456"
        case .production:
            // Production server URL — update before submission
            return "https://family-life-organizer-production.up.railway.app"
        }
    }

    // MARK: - App Metadata

    static let bundleID = "com.atlasatlantic.familylife"
    static let appName = "FamilyLife"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Feature Flags

    static var isAIRecipesEnabled: Bool {
        AIConsentManager.hasConsented
    }

    static var isHealthKitEnabled: Bool {
        true // Can be toggled for TestFlight builds
    }

    static var isLocationTrackingEnabled: Bool {
        true
    }
}
