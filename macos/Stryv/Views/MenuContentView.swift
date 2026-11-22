import SwiftUI

/// Everything in the menu bar popover. Sections are separated by space and one hairline,
/// on the popover's own translucent background.
struct MenuContentView: View {
    @EnvironmentObject private var model: BlockModel
    @EnvironmentObject private var overlay: BlockedOverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 18) {
                HelperNotice()
                if let block = model.activeBlock {
                    ActiveBlockView(block: block)
                } else {
                    BlockSetupView()
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(TypeScale.meta)
                        .foregroundStyle(Theme.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Hairline().padding(.vertical, 18)

            FocusMusicView()

            footer
                .padding(.top, 22)
        }
        .padding(18)
        .frame(width: 380)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stryv")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: model.activeBlock == nil ? .clear : Theme.ember.opacity(0.8), radius: 4)
                Text(statusText)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(model.activeBlock == nil ? Color.secondary : Theme.ember)
            }
        }
    }

    private var statusText: String {
        if let block = model.activeBlock {
            return "Locked in until \(Format.endTime(block.endsAt))"
        }
        switch model.helperState {
        case .ready: return "Ready"
        case .checking: return "Connecting"
        default: return "Needs setup"
        }
    }

    private var statusColor: Color {
        if model.activeBlock != nil { return Theme.ember }
        return model.helperState == .ready ? Color.green : Color.secondary.opacity(0.6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !overlay.isAccessibilityTrusted {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Turn on Accessibility for Stryv to cover blocked sites in your browser.")
                        .font(TypeScale.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Turn on") { overlay.requestAccessibility() }
                        .buttonStyle(TextActionStyle())
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Open at login")
                        .font(TypeScale.meta)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.ember)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(TypeScale.meta)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help(model.activeBlock == nil ? "Quit Stryv" : "Quitting doesn't end the block.")
            }
        }
    }
}

/// Shown only when the blocking helper needs installing or repairing.
private struct HelperNotice: View {
    @EnvironmentObject private var model: BlockModel

    var body: some View {
        switch model.helperState {
        case .ready, .checking:
            EmptyView()
        case .notInstalled, .notResponding, .outdated:
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(TypeScale.title)
                Text(message)
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle) {
                    Task { await model.installHelper() }
                }
                .buttonStyle(EmberButtonStyle())
                .disabled(model.isWorking)
            }
        }
    }

    private var title: String {
        switch model.helperState {
        case .outdated: "Update the blocker"
        case .notResponding: "The blocker isn't responding"
        default: "Install the blocker"
        }
    }

    private var message: String {
        switch model.helperState {
        case .outdated: "This version of Stryv needs a newer blocker. Updating keeps any running block."
        case .notResponding: "Reinstall it to fix this. Any running block is kept."
        default: "Stryv blocks sites with a small system helper. You'll enter your password once, and blocks keep running even if Stryv quits or the Mac restarts."
        }
    }

    private var buttonTitle: String {
        model.helperState == .notInstalled ? "Install blocker" : "Reinstall blocker"
    }
}
