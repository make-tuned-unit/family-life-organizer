import SwiftUI

/// The app's loading screen (session restore at launch): the family paddling
/// together on a loop, tagline beneath. Static crew under Reduce Motion; the
/// copy carries the meaning either way.
struct KinrowsLaunchView: View {
    var message: String? = nil

    var body: some View {
        ZStack {
            AmbientBackground(style: .home)
            VStack(spacing: DesignTokens.Spacing.sectionGap) {
                PaddlingCrewView(maxWidth: 300)
                VStack(spacing: DesignTokens.Spacing.rowVertical) {
                    Text("Kin that rows together.")
                        .font(.flDisplayItalic)
                        .foregroundStyle(WarmPalette.ink2)
                    if let message {
                        Text(message)
                            .font(.flFootnote)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignTokens.Spacing.large)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

#Preview("Launch") {
    KinrowsLaunchView(message: "Getting the household ready…")
}
