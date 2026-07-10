import SwiftUI

// MARK: - Cooking Mode
// Full-screen, flour-covered-hands step viewer: the current step is large and
// bright, neighbors are dimmed; the top/bottom halves of the screen are giant
// tap zones for previous/next; the display never sleeps mid-recipe.

struct CookingModeView: View {
    let recipe: RecipeSuggestion
    /// Called once when the cook taps "Done" on the last step.
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var showingIngredients = false

    private var steps: [String] {
        recipe.steps.isEmpty ? ["Follow your instincts — this recipe came without steps."] : recipe.steps
    }

    var body: some View {
        ZStack {
            WarmPalette.cream1.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                // Steps: previous and next visible but dimmed, current is the star.
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                stepView(index: index, text: step)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 40)
                    }
                    .onChange(of: currentStep) {
                        withAnimation(.smooth) {
                            proxy.scrollTo(currentStep, anchor: .center)
                        }
                    }
                }

                footer
            }

            // Giant tap zones — top half = back, bottom half = forward.
            // They sit behind the header/footer controls via allowsHitTesting
            // on a clear overlay column between them.
            VStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goBack() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goForward() }
            }
            .padding(.top, 90)
            .padding(.bottom, 110)
            .accessibilityHidden(true)
        }
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showingIngredients) { ingredientsSheet }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.flHeadline)
                    .foregroundStyle(WarmPalette.ink1)
                    .lineLimit(1)
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: currentStep)
            }
            Spacer()
            Button { showingIngredients = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WarmPalette.ink2)
                    .frame(width: 44, height: 44)
                    .background(WarmPalette.cardSurface, in: Circle())
            }
            .accessibilityLabel("Ingredients")
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink2)
                    .frame(width: 44, height: 44)
                    .background(WarmPalette.cardSurface, in: Circle())
            }
            .accessibilityLabel("Exit cooking mode")
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.top, 18)
    }

    private func stepView(index: Int, text: String) -> some View {
        let isCurrent = index == currentStep
        return HStack(alignment: .top, spacing: 16) {
            Text("\(index + 1)")
                .font(.flHeadline)
                .foregroundStyle(isCurrent ? WarmPalette.cream1 : WarmPalette.ink3)
                .frame(width: 34, height: 34)
                .background(
                    isCurrent ? AccentTheme.terracotta.color : WarmPalette.cream2,
                    in: Circle()
                )
            Text(text)
                .font(isCurrent ? .flTitle : .flBody)
                .foregroundStyle(WarmPalette.ink1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(isCurrent ? 1 : 0.35)
        .animation(.smooth(duration: 0.25), value: currentStep)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 56, height: 52)
                    .foregroundStyle(WarmPalette.ink2)
                    .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 18))
            }
            .disabled(currentStep == 0)
            .opacity(currentStep == 0 ? 0.4 : 1)
            .accessibilityLabel("Previous step")

            Button {
                if isLastStep {
                    onFinished()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } else {
                    goForward()
                }
            } label: {
                Text(isLastStep ? "Done — mark as cooked" : "Next step")
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.cream1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isLastStep ? WarmPalette.good : WarmPalette.ink1,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.bottom, 14)
    }

    private var ingredientsSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ingredients")
                    .font(.flScreenTitle)
                    .foregroundStyle(WarmPalette.ink1)
                    .padding(.bottom, 6)
                ForEach(recipe.ingredients) { ingredient in
                    HStack(spacing: 10) {
                        Image(systemName: ingredient.available ? "checkmark.circle.fill" : "cart")
                            .font(.system(size: 15))
                            .foregroundStyle(ingredient.available ? WarmPalette.good : WarmPalette.warn)
                        Text(ingredient.name)
                            .font(.flBody)
                            .foregroundStyle(WarmPalette.ink1)
                        Spacer()
                        if let qty = ingredient.quantity {
                            Text(qty)
                                .font(.flFootnote)
                                .foregroundStyle(WarmPalette.ink3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(WarmPalette.cream1)
    }

    // MARK: - Navigation

    private var isLastStep: Bool { currentStep == steps.count - 1 }

    private func goForward() {
        guard !isLastStep else { return }
        currentStep += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview("Cooking Mode") {
    CookingModeView(
        recipe: RecipeSuggestion(
            name: "Weeknight Chicken Stir-Fry",
            cookTime: 25,
            difficulty: "Easy",
            servings: 4,
            ingredients: [],
            steps: [
                "Slice the chicken into thin strips and season with salt and pepper.",
                "Heat oil in a wok over high heat until shimmering.",
                "Stir-fry the chicken until golden, about 4 minutes, then set aside.",
                "Add the vegetables and cook until crisp-tender.",
                "Return the chicken, add the sauce, and toss for one minute. Serve over rice."
            ]
        )
    ) {}
}
