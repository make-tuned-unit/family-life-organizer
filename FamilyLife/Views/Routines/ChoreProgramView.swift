import SwiftUI

/// The complete chores program: principles, age-banded chore ladders with
/// reward guidance, and the sources it rests on. Static content served by the
/// backend (`services/chores.js`), in the same shape as the sleep program.
struct ChoreProgramView: View {
    @Environment(APIService.self) private var api

    /// The band to open expanded — the child's current one, when known.
    var highlightBand: String? = nil

    @State private var template: ChoresTemplate?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expanded: Set<String> = []

    private let accent = TabAccent.routines.color

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if isLoading {
                    FLLoadingState(message: "Loading the program…").padding(.top, 60)
                } else if let template {
                    FLScreenHeader(
                        eyebrow: "Ages 2 to teen",
                        title: "Chores that stick",
                        subtitle: template.subtitle,
                        accent: accent
                    )

                    VStack(spacing: 16) {
                        disclaimer(template.disclaimer)
                        principles(template.principles)

                        ForEach(Array(template.bands.enumerated()), id: \.element.id) { index, band in
                            BandCard(index: index + 1, band: band, accent: accent,
                                     isExpanded: expanded.contains(band.key)) {
                                if expanded.contains(band.key) { expanded.remove(band.key) } else { expanded.insert(band.key) }
                            }
                        }

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
        Label(text, systemImage: "info.circle.fill")
            .font(.flFootnote)
            .foregroundStyle(WarmPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flCard(tint: accent.opacity(0.06))
    }

    private func principles(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the research agrees on")
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink1)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                    Text(item)
                        .font(.flSubheadline)
                        .foregroundStyle(WarmPalette.ink2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard()
    }

    private func sources(_ sources: [SleepSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink1)
            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.top, 3)
                            Text(source.title)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .flCard()
    }

    private func load() async {
        do {
            template = try await api.fetchChoresTemplate()
            if let highlightBand { expanded = [highlightBand] }
            else if let first = template?.bands.first { expanded = [first.key] }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the program. Pull to try again."
        }
        isLoading = false
    }
}

private struct BandCard: View {
    let index: Int
    let band: ChoreBand
    let accent: Color
    let isExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Text("\(index)")
                        .font(.flSubheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(band.title)
                            .font(.flHeadline)
                            .foregroundStyle(WarmPalette.ink1)
                        Text("\(band.age_label) · \(band.chore_count)")
                            .font(.flCaption)
                            .foregroundStyle(WarmPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WarmPalette.ink4)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(band.description)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)

                section("Chores that fit") {
                    ForEach(band.suggested) { s in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: s.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(accent)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).font(.flSubheadline).foregroundStyle(WarmPalette.ink1)
                                if let note = s.note {
                                    Text(note).font(.flCaption).foregroundStyle(WarmPalette.ink3)
                                }
                            }
                        }
                    }
                }

                section("How to run it") {
                    ForEach(Array(band.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.flSubheadline.weight(.semibold))
                                .foregroundStyle(accent)
                            Text(step).font(.flSubheadline).foregroundStyle(WarmPalette.ink2)
                        }
                    }
                }

                section("Allowance & rewards") {
                    Text(band.allowance.label)
                        .font(.flSubheadline.weight(.semibold))
                        .foregroundStyle(WarmPalette.ink1)
                    Text(band.allowance.note)
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }

                if !band.tips.isEmpty {
                    section("Worth knowing") {
                        ForEach(band.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AccentTheme.saffron.color)
                                    .padding(.top, 3)
                                Text(tip).font(.flFootnote).foregroundStyle(WarmPalette.ink2)
                            }
                        }
                    }
                }

                if let next = band.next_band {
                    Label(next, systemImage: "arrow.right.circle.fill")
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                }
            }
        }
        .padding(16)
        .flCard(tint: isExpanded ? accent.opacity(0.04) : .clear)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.flOverline)
                .foregroundStyle(WarmPalette.ink3)
            content()
        }
    }
}

#Preview {
    NavigationStack { ChoreProgramView(highlightBand: "toddler") }
        .environment(APIService())
}
