import SwiftUI

/// The screen you see on a blocked site, drawn over the browser's page area.
struct BlockedOverlayView: View {
    @ObservedObject var state: BlockedOverlayState
    var onCloseTab: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.lockGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.lock.opacity(0.45), radius: 18, y: 6)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(state.domain)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("is blocked while you focus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        Text(Format.countdown(state.endsAt.timeIntervalSince(context.date)))
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("left · ends at \(Format.endTime(state.endsAt))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                QuoteView(quote: state.quote)
                    .padding(.top, 8)

                Button(action: onCloseTab) {
                    Label("Close this tab", systemImage: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(Capsule().fill(.white))
                .padding(.top, 6)
            }
            .padding(32)
        }
        .ignoresSafeArea()
    }
}

/// The rotating quote, fading between quotes as they change.
private struct QuoteView: View {
    let quote: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.lockGradient)
            ZStack {
                Text(quote)
                    .id(quote)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: 520)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
