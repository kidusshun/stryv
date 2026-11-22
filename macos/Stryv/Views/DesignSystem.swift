import SwiftUI

/// Stryv's palette, taken from the original app's theme (tailwind.config.js). Text and
/// hairlines use adaptive system colors so the translucent popover stays legible in light
/// and dark mode.
enum Theme {
    static let ember = Color(hex: 0xE8581A)
    static let flame = Color(hex: 0xFF9A4A)
    static let emberDeep = Color(hex: 0xB93A12)
    static let amber = Color(hex: 0xFFB267)

    /// The fuse: burnt at the start, hottest at the tip.
    static let fuseGradient = LinearGradient(colors: [emberDeep, ember, flame], startPoint: .leading, endPoint: .trailing)

    static let hairline = Color.primary.opacity(0.1)
    static let wash = Color.primary.opacity(0.055)
    static let washStrong = Color.primary.opacity(0.09)

    // Names used across the app.
    static let accent = ember
    static let lock = ember
    static let lockGradient = LinearGradient(colors: [ember, flame], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Type scale: 11 (meta), 13 (body), 15 (titles), 40 (time numerals).
enum TypeScale {
    static let meta = Font.system(size: 11)
    static let metaStrong = Font.system(size: 11, weight: .medium)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static func numerals(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// A text field in a soft well, with a leading icon and optional trailing content.
struct InputWell<Trailing: View>: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var font: Font = TypeScale.body
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .onSubmit(onSubmit)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.wash))
    }
}

extension InputWell where Trailing == EmptyView {
    init(systemImage: String, placeholder: String, text: Binding<String>, font: Font = TypeScale.body, onSubmit: @escaping () -> Void = {}) {
        self.init(systemImage: systemImage, placeholder: placeholder, text: text, font: font, onSubmit: onSubmit) { EmptyView() }
    }
}

/// Lays children out left to right, wrapping onto new lines (used for site chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A site's initial in a small disc.
struct SiteMark: View {
    let domain: String
    var size: CGFloat = 16

    var body: some View {
        Text(domain.prefix(1).uppercased())
            .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.washStrong))
    }
}

/// Overlapping site initials: a compact picture of what's blocked.
struct SiteStack: View {
    let domains: [String]
    var limit = 5

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(domains.prefix(limit).enumerated()), id: \.offset) { _, domain in
                SiteMark(domain: domain, size: 20)
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.6), lineWidth: 1.5))
            }
        }
    }
}

/// A site as a removable chip.
struct SiteChip: View {
    let domain: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            SiteMark(domain: domain, size: 15)
            Text(domain)
                .font(.system(size: 12))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(domain)")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, onRemove == nil ? 9 : 5)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.wash))
    }
}

/// A duration preset: quiet text until chosen, then ember.
struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.ember : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Theme.ember.opacity(0.14) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The one strong action: solid ember with Stryv's glow.
struct EmberButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.bodyStrong)
            .foregroundStyle(isEnabled ? (prominent ? Color.white : Theme.ember) : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .shadow(color: Theme.ember.opacity(prominent && isEnabled ? 0.35 : 0), radius: 12, y: 2)
    }

    private func fill(pressed: Bool) -> Color {
        guard isEnabled else { return Theme.wash }
        guard prominent else { return Theme.ember.opacity(0.12) }
        return pressed ? Theme.emberDeep : Theme.ember
    }
}

/// Quiet secondary action.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(configuration.isPressed ? Theme.washStrong : Theme.wash))
    }
}

/// Small text action, like "Edit" or "Add site".
struct TextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.metaStrong)
            .foregroundStyle(Theme.ember)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Round player control.
struct IconButton: View {
    let systemImage: String
    var size: CGFloat = 28
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(filled ? Color.white : Color.primary.opacity(0.8))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Theme.ember : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The burning fuse: a line that burns down from left to right with a glowing ember tip.
struct Fuse: View {
    /// 0 = just lit, 1 = burnt out.
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let tipX = max(5, min(width - 5, width * progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.washStrong).frame(height: 4)
                Capsule().fill(Theme.fuseGradient).frame(width: tipX, height: 4)
                Circle()
                    .fill(Theme.flame)
                    .frame(width: 10, height: 10)
                    .shadow(color: Theme.flame.opacity(0.9), radius: 6)
                    .shadow(color: Theme.ember.opacity(0.6), radius: 14)
                    .offset(x: tipX - 5)
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: 14)
        .animation(.linear(duration: 1), value: progress)
    }
}
