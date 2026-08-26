import SwiftUI

/// Product vignettes for the pre-signup tour. These are the "taste" of Kinrows —
/// they look like the real calendar / lists / people UI, not a feature bullet list.

struct OnboardingAvatarCluster: View {
    private let people = ["Sophie Fairbanks", "Jesse Fairbanks", "Avery Fairbanks"]

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, name in
                FamilyAvatar(
                    initial: String(name.prefix(1)),
                    size: 52,
                    name: name
                )
                .overlay {
                    Circle().stroke(WarmPalette.cream1, lineWidth: 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A household of three")
    }
}

struct OnboardingChipRow: View {
    let items: [(icon: String, tint: Color, text: String)]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.inset) {
            ForEach(items, id: \.text) { item in
                VStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .frame(width: 36, height: 36)
                        .background(item.tint.opacity(DesignTokens.Opacity.badgeFill), in: Circle())
                    Text(item.text)
                        .font(.flCaption2.weight(.medium))
                        .foregroundStyle(WarmPalette.ink2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard()
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingWeekRail: View {
    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    private let sophie = "Sophie Fairbanks"
    private let jesse = "Jesse Fairbanks"

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardGap) {
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, label in
                    Text(label)
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(i == 1 ? WarmPalette.ink1 : WarmPalette.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        if i == 1 {
                            pill("Swim", name: sophie)
                        } else if i == 3 {
                            pill("Dentist", name: jesse)
                        } else if i == 4 {
                            pill("Tacos", name: sophie)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(minHeight: 56, alignment: .top)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: TabAccent.calendar.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A shared week. Sophie has swim on Tuesday and tacos on Friday. Jesse has the dentist on Thursday.")
    }

    private func pill(_ title: String, name: String) -> some View {
        Text(title)
            .font(.flCaption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(PersonPalette.color(for: name), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct OnboardingGroceryMock: View {
    var animateCheck: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var milkChecked = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardGap) {
            groceryRow("Milk", checked: milkChecked, tint: AccentTheme.sage.color)
            groceryRow("Cilantro", checked: false, tint: AccentTheme.terracotta.color)
            groceryRow("Tortillas", checked: false, tint: AccentTheme.sage.color)

            HStack(spacing: DesignTokens.Spacing.inset) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AccentTheme.terracotta.color)
                    .frame(width: 28, height: 28)
                    .background(AccentTheme.terracotta.color.opacity(DesignTokens.Opacity.badgeFill), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dinner: taco night")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("You have everything but cilantro.")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
            .padding(.top, DesignTokens.Spacing.tinyLabel)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: AccentTheme.sage.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A grocery list updating from the aisle, and taco night from what's in the pantry.")
        .task(id: animateCheck) {
            guard animateCheck else { return }
            if reduceMotion {
                milkChecked = true
                return
            }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeInOut(duration: 0.35)) { milkChecked = true }
        }
    }

    private func groceryRow(_ title: String, checked: Bool, tint: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.chipPadding) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(checked ? tint : WarmPalette.ink4)
            Text(title)
                .font(.flSubheadline)
                .foregroundStyle(checked ? WarmPalette.ink3 : WarmPalette.ink1)
                .strikethrough(checked, color: WarmPalette.ink4)
            Spacer()
        }
    }
}

struct OnboardingPeopleMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardGap) {
            HStack(spacing: DesignTokens.Spacing.chipPadding) {
                FamilyAvatar(initial: "S", size: 40, name: "Sophie Fairbanks")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Partner joins with one code")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("K7MX-2P9Q")
                        .font(.system(.footnote, design: .monospaced).weight(.bold))
                        .foregroundStyle(AccentTheme.terracotta.color)
                }
            }
            HStack(spacing: DesignTokens.Spacing.chipPadding) {
                FamilyAvatar(initial: "A", size: 40, name: "Avery Fairbanks")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kids live in People")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text("No phone, no account needed.")
                        .font(.flCaption)
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: AccentTheme.terracotta.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your partner joins with one invite code. Kids live in People with no phone needed.")
    }
}

struct OnboardingConciergeMock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reply: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.inset) {
            prompt("Add swim practice every Tuesday at 4") {
                reply = "Done — swim is on the calendar every Tuesday at 4, colored for Sophie."
            }
            prompt("What should we make for dinner tonight?") {
                reply = "Taco night works: you have everything but cilantro. Added it to Groceries."
            }
            if let reply {
                HStack {
                    Text(reply)
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink1)
                        .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                        .padding(.vertical, DesignTokens.Spacing.rowVertical)
                        .background(WarmPalette.cream2, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
                    Spacer(minLength: DesignTokens.Spacing.large)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .flCard(tint: AccentTheme.saffron.color)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: reply)
    }

    private func prompt(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: DesignTokens.Spacing.large)
                Text(text)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.cream1)
                    .padding(.horizontal, DesignTokens.Spacing.chipPadding)
                    .padding(.vertical, DesignTokens.Spacing.rowVertical)
                    .background(WarmPalette.ink1, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows what the Concierge would do")
    }
}

#Preview("Week rail") {
    OnboardingWeekRail()
        .padding()
        .background { AmbientBackground(style: .calendar) }
}

#Preview("Grocery") {
    OnboardingGroceryMock(animateCheck: true)
        .padding()
        .background { AmbientBackground(style: .pantry) }
}
