import SwiftUI
import AVFoundation

// MARK: - Family Avatar
// Uses Circle fill + overlay — NO .clipShape, NO offscreen render pass.

struct FamilyAvatar: View {
    let initial: String
    var size: CGFloat = 32
    /// Full name for identity color. Pass it whenever you have it — hashing
    /// the initial alone gives everyone starting with "J" the same color.
    var name: String? = nil

    var body: some View {
        Circle()
            .fill(PersonPalette.gradient(for: name ?? initial.uppercased()))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().stroke(.white.opacity(0.7), lineWidth: 1.5)
            }
    }
}

// MARK: - Profile Avatar (current user only)

struct ProfileAvatar: View {
    @Environment(AuthService.self) private var auth
    var size: CGFloat = 32
    var borderColor: Color = AccentTheme.sage.color
    var borderWidth: CGFloat = 2

    var body: some View {
        if let source = auth.profileUIImage {
            Image(uiImage: Self.preRenderedCircle(
                source, diameter: size,
                borderColor: UIColor(borderColor),
                borderWidth: borderWidth
            ))
        } else {
            Circle()
                .fill(Color.green.opacity(0.6))
                .frame(width: size, height: size)
                .overlay {
                    Text(auth.currentUser?.name.prefix(1).uppercased() ?? "?")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
        }
    }

    /// Pre-renders a UIImage as a perfect circle with border baked in.
    /// The toolbar cannot distort a pre-rendered bitmap.
    static func preRenderedCircle(
        _ source: UIImage,
        diameter: CGFloat,
        borderColor: UIColor,
        borderWidth: CGFloat
    ) -> UIImage {
        let totalSize = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { _ in
            let borderRect = CGRect(origin: .zero, size: totalSize)
            borderColor.setFill()
            UIBezierPath(ovalIn: borderRect).fill()

            let imageRect = borderRect.insetBy(dx: borderWidth, dy: borderWidth)
            UIBezierPath(ovalIn: imageRect).addClip()

            let imgSize = source.size
            let scale = max(imageRect.width / imgSize.width, imageRect.height / imgSize.height)
            let drawW = imgSize.width * scale
            let drawH = imgSize.height * scale
            source.draw(in: CGRect(
                x: imageRect.midX - drawW / 2,
                y: imageRect.midY - drawH / 2,
                width: drawW, height: drawH
            ))
        }
    }
}

// MARK: - User Avatar (any user — checks profile image cache, falls back to initials)

struct UserAvatar: View {
    let name: String
    var userId: Int? = nil
    var size: CGFloat = 32
    @Environment(AuthService.self) private var auth
    @Environment(ProfileImageCache.self) private var profileCache

    var body: some View {
        if isCurrentUser, let uiImage = auth.profileUIImage {
            profileImage(uiImage)
        } else if let uid = userId, let img = profileCache.image(for: uid) {
            profileImage(img)
        } else {
            FamilyAvatar(initial: String(name.prefix(1)).uppercased(), size: size, name: name)
        }
    }

    private var isCurrentUser: Bool {
        guard let user = auth.currentUser else { return false }
        return name.localizedCaseInsensitiveCompare(user.name) == .orderedSame
            || name.localizedCaseInsensitiveCompare(user.username) == .orderedSame
    }

    private func profileImage(_ img: UIImage) -> some View {
        Image(uiImage: ProfileAvatar.preRenderedCircle(
            img, diameter: size,
            borderColor: .clear,
            borderWidth: 0
        ))
        .resizable()
        .frame(width: size, height: size)
    }
}

// MARK: - Group Avatar

/// Avatar for a group/household — shows its uploaded image if set, otherwise
/// falls back to the group's initial. Lazily fetches the image by group id.
struct GroupAvatar: View {
    let groupId: Int
    let name: String
    var size: CGFloat = 32
    @Environment(APIService.self) private var api
    @Environment(ProfileImageCache.self) private var profileCache

    var body: some View {
        Group {
            if let img = profileCache.groupImage(for: groupId) {
                Image(uiImage: ProfileAvatar.preRenderedCircle(
                    img, diameter: size, borderColor: .clear, borderWidth: 0
                ))
                .resizable()
                .frame(width: size, height: size)
            } else {
                FamilyAvatar(initial: String(name.prefix(1)).uppercased(), size: size)
            }
        }
        .onAppear { profileCache.fetchGroupIfNeeded(groupId: groupId, api: api) }
    }
}

// MARK: - Screen Header
// THE branded screen opener: accent eyebrow, big warm title, optional
// subtitle. Every full-screen surface opens with this so the app reads as
// one product, not sixteen features.

struct FLScreenHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var accent: Color = WarmPalette.ink3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.flOverline)
                .foregroundStyle(accent)
                .tracking(0.4)
            Text(title)
                .font(.flScreenTitle)
                .foregroundStyle(WarmPalette.ink1)
            if let subtitle {
                Text(subtitle)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }
}

// MARK: - Loading State
// The branded stand-in for a bare ProgressView: warm-tinted spinner with an
// optional quiet line of copy, centered in the content area.

struct FLLoadingState: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(WarmPalette.ink2)
            if let message {
                Text(message)
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Presence Chip

struct PresenceChip: View {
    let initial: String
    let name: String
    let status: String
    let statusColor: Color
    var showTrip: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FamilyAvatar(initial: initial, size: 28, name: name)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.flFootnote.weight(.semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(status)
                        .font(.flOverline)
                        .foregroundStyle(WarmPalette.ink3)
                }
            }
            if showTrip {
                Image(systemName: "car.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TabAccent.home.color)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .background(WarmPalette.cardSurface, in: Capsule())
    }
}

// MARK: - Stat Tile

struct WarmStatTile: View {
    let label: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.flOverline)
                .foregroundStyle(WarmPalette.ink3)
                .tracking(0.4)
            Text(value)
                .font(.flTitle)
                .foregroundStyle(WarmPalette.ink1)
                .contentTransition(.numericText())
            Text(sub)
                .font(.flCaption)
                .foregroundStyle(WarmPalette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.tile))
    }
}

// MARK: - Agenda Row

struct WarmAgendaRow: View {
    let time: String
    let title: String
    let subtitle: String
    var tagInitial: String? = nil
    /// Full name behind tagInitial — gives the avatar its per-person color.
    var tagName: String? = nil
    var isAuto: Bool = false
    /// Checked state for task rows — draws the filled dot + strikethrough.
    var isDone: Bool = false
    /// When set, the leading circle becomes a tappable check-off button.
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if isAuto {
                // Task rows show a checkable circle in the left column to match the Lists layout.
                Group {
                    if let onToggle {
                        Button(action: onToggle) {
                            checkCircle
                        }
                        .buttonStyle(.plain)
                    } else {
                        checkCircle
                    }
                }
                .frame(minWidth: 44, alignment: .leading)
            } else {
                Text(time)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(WarmPalette.ink1)
                    .frame(minWidth: 44, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.flSubheadline.weight(.semibold))
                    .foregroundStyle(isDone ? WarmPalette.ink3 : WarmPalette.ink1)
                    .strikethrough(isDone, color: WarmPalette.ink4)
                Text(subtitle)
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            if isAuto {
                if !isDone {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundStyle(TabAccent.home.color)
                        .frame(width: 22, height: 22)
                        .background(TabAccent.home.color.opacity(0.15), in: Circle())
                }
            } else if let initial = tagInitial {
                FamilyAvatar(initial: initial, size: 22, name: tagName)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var checkCircle: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isDone ? WarmPalette.good : WarmPalette.ink4)
            .scaleEffect(isDone ? 1.1 : 1)
    }
}

// MARK: - Glass Divider

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(WarmPalette.ink1.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}

// MARK: - Icon Button

struct GlassIconButton: View {
    let systemName: String
    /// VoiceOver label describing the action (e.g. "Add list"). Falls back to
    /// the SF Symbol name so the control is never unlabeled.
    var accessibilityLabel: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WarmPalette.ink2)
        }
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

// MARK: - Section Header

struct WarmSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink1)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.flFootnote)
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.horizontalMargin + 4)
    }
}

// MARK: - Filter Chip
// Uses background(in: Capsule()) — NO .clipShape.

struct WarmChip: View {
    let label: String
    var isActive: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? WarmPalette.cream1 : WarmPalette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? WarmPalette.ink1 : WarmPalette.cardSurface, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.clear : WarmPalette.ink1.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Card

struct EventCard: View {
    let time: String
    let duration: String
    let title: String
    let location: String
    let color: Color
    var attendees: [String] = []
    /// Full names parallel to `attendees` — gives each avatar its person color.
    var attendeeNames: [String] = []
    var recurring: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(time)
                        .font(.flSubheadline.weight(.bold))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    Text(duration + (recurring ? " recurring" : ""))
                        .font(.flFootnote)
                        .foregroundStyle(WarmPalette.ink3)
                }
                Text(title)
                    .font(.flSubheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                    Text(location)
                }
                .font(.flFootnote)
                .foregroundStyle(WarmPalette.ink3)
            }

            if !attendees.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(attendees.enumerated()), id: \.offset) { index, initial in
                        FamilyAvatar(
                            initial: initial, size: 22,
                            name: index < attendeeNames.count ? attendeeNames[index] : nil
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

// MARK: - Progress Bar

struct WarmProgressBar: View {
    let progress: Double
    var color: Color = TabAccent.home.color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(WarmPalette.ink1.opacity(0.08))
                RoundedRectangle(cornerRadius: 999)
                    .fill(color)
                    .frame(width: geo.size.width * min(progress, 1.0))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Inline Error

/// The house style for surfacing a failure: a dismissible warm banner shown
/// in-content, never a modal alert. Pair with the `.inlineError(_:onDismiss:)`
/// modifier so it drops in from the top of any screen or sheet.
struct InlineErrorBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(WarmPalette.bad)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WarmPalette.ink3)
            }
        }
        .padding(12)
        .background(WarmPalette.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WarmPalette.bad.opacity(0.25), lineWidth: 1))
    }
}

extension View {
    /// Drop-in replacement for error `.alert(...)`: shows `message` as an inline
    /// banner pinned to the top of the content when non-nil. No-op when nil.
    @ViewBuilder
    func inlineError(_ message: String?, onDismiss: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .top) {
            if let message {
                InlineErrorBanner(message: message, onDismiss: onDismiss)
                    .padding(.horizontal, DesignTokens.Spacing.horizontalMargin)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Empty State

// Action-first: an empty state should offer the next step, not a dead end.
// Frame copy as possibility ("Plan your first trip"), not absence ("No trips").
struct WarmEmptyState: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    /// Primary path out of the empty state (e.g. "Add an item").
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(WarmPalette.ink4)
            Text(title)
                .font(.flHeadline)
                .foregroundStyle(WarmPalette.ink2)
            if let description {
                Text(description)
                    .font(.flSubheadline)
                    .foregroundStyle(WarmPalette.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.large)
            }
            if let actionLabel, let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(.flSubheadline.weight(.semibold))
                }
                .buttonStyle(.flSecondary)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
