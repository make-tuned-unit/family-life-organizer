import SwiftUI

/// Apple Guideline 5.1.2(i): Apps must clearly disclose where personal data
/// will be shared with third-party AI and obtain explicit permission.
/// This view must be shown before first use of the Cook/recipe suggestion feature.
struct AIDisclosureView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(colors: [WarmPalette.peach, AccentTheme.terracotta.color], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("AI-Powered Recipes")
                    .font(.flTitle)
                    .foregroundStyle(WarmPalette.ink1)

                Text("The recipe suggestion feature sends your pantry items and query to **Claude by Anthropic** to generate personalized recipes.")
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 12) {
                    disclosureRow(icon: "arrow.up.doc", text: "Your pantry items and food query are sent to Anthropic's API")
                    disclosureRow(icon: "shield.checkered", text: "Data is not stored by Anthropic after generating your response")
                    disclosureRow(icon: "person.crop.circle.badge.xmark", text: "No personal identifiers (name, location) are shared")
                    disclosureRow(icon: "xmark.circle", text: "You can use the app without this feature")
                }
                .padding(16)
                .background(WarmPalette.ink1.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onAccept) {
                    Text("Allow AI Suggestions")
                }
                .buttonStyle(.flCTA)

                Button(action: onDecline) {
                    Text("No Thanks")
                        .font(.flBody.weight(.medium))
                        .foregroundStyle(WarmPalette.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }

                Text("You can change this later in Settings.")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background { AmbientBackground(style: .cook) }
    }

    private func disclosureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(TabAccent.cook.color)
                .frame(width: 20)
            Text(text)
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink2)
        }
    }
}

// MARK: - Consent Storage

enum AIConsentManager {
    private static let key = "ai_recipe_consent_granted"

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func grant() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func revoke() {
        UserDefaults.standard.set(false, forKey: key)
    }
}

#Preview {
    AIDisclosureView(onAccept: {}, onDecline: {})
}
