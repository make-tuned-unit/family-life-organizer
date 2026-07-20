import SwiftUI

// MARK: - Guidance card (shown on a sleep_training routine's detail screen)

/// The current age phase for a child, with the recommended method and a link to
/// the full program. Leads with the "ready to train?" state so a newborn's
/// caregiver isn't pushed toward formal training too early.
struct SleepGuidanceCard: View {
    let guidance: SleepGuidance

    private let accent = TabAccent.routines.color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ageLabel)
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(guidance.current_phase.title)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                }
                Spacer()
            }

            Text(guidance.current_phase.age_label)
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)

            if !guidance.ready_for_training {
                Label("Too young for formal sleep training — focus on rhythm and safe sleep for now.", systemImage: "info.circle.fill")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
            }

            if let method = guidance.current_phase.method {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recommended: \(method.name)")
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(method.summary)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }

            NavigationLink {
                SleepTrainingProgramView()
            } label: {
                Text("View the full program")
                    .font(.flSubheadline.weight(.semibold))
            }
            .buttonStyle(.flCTA(fill: accent))
        }
        .padding(16)
        .flCard(tint: accent.opacity(0.05))
    }

    private var ageLabel: String {
        if guidance.age_months < 4 {
            return "\(guidance.age_weeks) weeks old"
        }
        let years = guidance.age_months / 12
        let months = guidance.age_months % 12
        if years >= 1 {
            return months == 0 ? "\(years)y old" : "\(years)y \(months)m old"
        }
        return "\(guidance.age_months) months old"
    }
}

// MARK: - Full program

/// The complete, research-grounded sleep-training program: safe-sleep rules,
/// age-banded phases, a method glossary, and sources. Static content served by
/// the backend.
struct SleepTrainingProgramView: View {
    @Environment(APIService.self) private var api

    @State private var template: SleepTrainingTemplate?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openInfo = false

    private let accent = TabAccent.routines.color

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if isLoading {
                    FLLoadingState(message: "Loading the program…").padding(.top, 60)
                } else if let template {
                    FLScreenHeader(
                        eyebrow: "Newborn – 4 years",
                        title: "Sleep training",
                        subtitle: template.subtitle,
                        accent: accent
                    )

                    VStack(spacing: 16) {
                        disclaimer(template.disclaimer)
                        safeSleep(template.safe_sleep)

                        ForEach(Array(template.phases.enumerated()), id: \.element.id) { index, phase in
                            PhaseCard(index: index + 1, phase: phase)
                        }

                        methodGlossary(template.methods)
                        sources(template.sources)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.bottomBuffer)
        }
        .background { AmbientBackground(style: .home) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .inlineError(errorMessage) { errorMessage = nil }
        .task { await load() }
    }

    private func disclaimer(_ text: String) -> some View {
        Label(text, systemImage: "cross.case.fill")
            .font(.flFootnote)
            .foregroundStyle(WarmPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flCard(tint: accent.opacity(0.06))
    }

    private func safeSleep(_ rules: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safe sleep — every sleep, every phase", systemImage: "checkmark.shield.fill")
                .font(.flSubheadline.weight(.semibold))
                .foregroundStyle(WarmPalette.ink1)
            ForEach(rules, id: \.self) { rule in
                bullet(rule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .flCard()
    }

    private func methodGlossary(_ methods: [SleepMethod]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The methods")
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink1)
            ForEach(methods) { method in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(method.name)
                            .font(.flSubheadline.weight(.semibold))
                            .foregroundStyle(WarmPalette.ink1)
                        Spacer()
                        Text(method.ages)
                            .font(.flCaption2)
                            .foregroundStyle(accent)
                    }
                    Text(method.summary)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .flCard()
            }
        }
    }

    private func sources(_ sources: [SleepSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.flSubheadline.weight(.semibold))
                .foregroundStyle(WarmPalette.ink2)
            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        Text(source.title)
                            .font(.flFootnote)
                            .foregroundStyle(accent)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(text)
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        do {
            template = try await api.fetchSleepTrainingTemplate()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the program. Please try again."
        }
        isLoading = false
    }
}

private struct PhaseCard: View {
    let index: Int
    let phase: SleepPhase

    private let accent = TabAccent.routines.color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.flCaption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(phase.title)
                        .font(.flHeadline)
                        .foregroundStyle(WarmPalette.ink1)
                    Text(phase.age_label)
                        .font(.flCaption.weight(.medium))
                        .foregroundStyle(accent)
                }
            }

            Text(phase.description)
                .font(.flSubheadline)
                .foregroundStyle(WarmPalette.ink2)

            if let method = phase.method {
                Text("Recommended: \(method.name)")
                    .font(.flFootnote.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            if !phase.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily steps")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    ForEach(phase.steps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(accent)
                                .padding(.top, 1)
                            Text(step)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if !phase.tips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tips")
                        .font(.flCaption.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink3)
                    ForEach(phase.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 12))
                                .foregroundStyle(AccentTheme.saffron.color)
                                .padding(.top, 1)
                            Text(tip)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard()
    }
}

#Preview {
    NavigationStack {
        SleepTrainingProgramView()
    }
    .environment(APIService())
}
