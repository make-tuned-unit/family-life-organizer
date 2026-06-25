import SwiftUI
import AVFoundation

// MARK: - Family Avatar
// Uses Circle fill + overlay — NO .clipShape, NO offscreen render pass.

struct FamilyAvatar: View {
    let initial: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Self.gradient(for: initial))
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

    private static let palette: [(Color, Color)] = [
        (Color(hex: "#c46a4a"), Color(hex: "#8a3e2a")),
        (Color(hex: "#d99a3c"), Color(hex: "#a86a1c")),
        (Color(hex: "#7ba05b"), Color(hex: "#4a6a35")),
        (Color(hex: "#6b8aa0"), Color(hex: "#3a5870")),
        (Color(hex: "#b97090"), Color(hex: "#7a4868")),
        (Color(hex: "#8a7468"), Color(hex: "#5a463a")),
        (Color(hex: "#6a9a8a"), Color(hex: "#3a6a5a")),
        (Color(hex: "#9a6ab0"), Color(hex: "#6a3a80")),
    ]

    private static func gradient(for initial: String) -> LinearGradient {
        let hash = initial.uppercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let pair = palette[abs(hash) % palette.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            FamilyAvatar(initial: String(name.prefix(1)).uppercased(), size: size)
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

// MARK: - Presence Chip

struct PresenceChip: View {
    let initial: String
    let name: String
    let status: String
    let statusColor: Color
    var showTrip: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FamilyAvatar(initial: initial, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(status)
                        .font(.system(size: 11))
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WarmPalette.ink3)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .default))
                .foregroundStyle(WarmPalette.ink1)
            Text(sub)
                .font(.system(size: 11))
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
    var isAuto: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if isAuto {
                // Task rows show a checkable circle in the left column to match the Lists layout.
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(WarmPalette.ink4)
                    .frame(minWidth: 44, alignment: .leading)
            } else {
                Text(time)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(WarmPalette.ink1)
                    .frame(minWidth: 44, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WarmPalette.ink1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(WarmPalette.ink3)
            }

            Spacer()

            if isAuto {
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(TabAccent.home.color)
                    .frame(width: 22, height: 22)
                    .background(TabAccent.home.color.opacity(0.15), in: Circle())
            } else if let initial = tagInitial {
                FamilyAvatar(initial: initial, size: 22)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
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
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WarmPalette.ink2)
        }
    }
}

// MARK: - Section Header

struct WarmSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(WarmPalette.ink1)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13))
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
    var recurring: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(time)
                        .font(.system(size: 15, weight: .bold, design: .default))
                        .foregroundStyle(WarmPalette.ink1)
                    Spacer()
                    Text(duration + (recurring ? " recurring" : ""))
                        .font(.system(size: 13))
                        .foregroundStyle(WarmPalette.ink3)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                    Text(location)
                }
                .font(.system(size: 13))
                .foregroundStyle(WarmPalette.ink3)
            }

            if !attendees.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(attendees.enumerated()), id: \.offset) { _, initial in
                        FamilyAvatar(initial: initial, size: 22)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .background(WarmPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20))
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

// MARK: - Empty State

struct WarmEmptyState: View {
    let title: String
    let systemImage: String
    var description: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(WarmPalette.ink4)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WarmPalette.ink2)
            if let description {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(WarmPalette.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
