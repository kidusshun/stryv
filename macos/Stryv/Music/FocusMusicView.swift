import SwiftUI

/// Focus music as a now-playing strip. Expanding it reveals seeking, volume, playlists and the
/// audio/video switch.
struct FocusMusicView: View {
    @EnvironmentObject private var player: FocusPlayer
    @AppStorage("focusMusicExpanded") private var isExpanded = false
    @State private var isAdding = false
    @State private var newLink = ""
    @State private var newName = ""
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAdding {
                addForm
            } else if player.selectedPlaylist == nil {
                emptyState
            } else {
                strip
                if case .failed(let message) = player.state {
                    failure(message)
                }
                if isExpanded {
                    details
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Strip

    private var strip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Artwork(url: player.artworkURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.trackTitle ?? (player.state == .loading ? "Loading playlist…" : "Focus music"))
                        .font(TypeScale.bodyStrong)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(player.trackTitle ?? "")
                    HStack(spacing: 6) {
                        playlistMenu
                        if player.trackCount > 0 {
                            Text("\(player.trackIndex + 1)/\(player.trackCount)")
                                .font(TypeScale.meta.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .layoutPriority(1)
                if player.state == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                } else {
                    IconButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", size: 32, filled: true) {
                        player.togglePlayback()
                    }
                    .help(player.isPlaying ? "Pause" : "Play")
                }
                IconButton(systemImage: "forward.fill", size: 26) { player.nextTrack() }
                    .help("Next track")
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Fewer controls" : "Volume, seeking, video and playlists")
            }
            if !isExpanded {
                ThinProgress(fraction: player.duration > 0 ? player.position / player.duration : 0)
            }
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if player.showsVideo {
                VideoSurface(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ProgressScrubber(position: player.position, duration: player.duration) { player.seek(to: $0) }
            HStack(spacing: 10) {
                IconButton(systemImage: "backward.fill", size: 26) { player.previousTrack() }
                    .help("Previous track")
                Image(systemName: volumeIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Slider(value: $player.volume, in: 0...100)
                    .controlSize(.small)
                    .tint(Theme.ember)
                    .frame(minWidth: 150, maxWidth: .infinity)
                    .help("Volume \(Int(player.volume))%")
                Picker("Mode", selection: $player.showsVideo) {
                    Image(systemName: "waveform").help("Audio only").tag(false)
                    Image(systemName: "play.rectangle").help("Show video").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var volumeIcon: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func failure(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(message)
                .font(TypeScale.meta)
                .foregroundStyle(Theme.ember)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Try again") { player.reload() }
                .buttonStyle(TextActionStyle())
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Play a YouTube playlist while you work. It keeps playing while YouTube is blocked.")
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a playlist") { isAdding = true }
                .buttonStyle(TextActionStyle())
        }
    }

    // MARK: Playlists

    private var playlistMenu: some View {
        Menu {
            ForEach(player.playlists) { playlist in
                Button {
                    player.select(playlist.id)
                } label: {
                    if playlist.id == player.selectedID {
                        Label(playlist.name, systemImage: "checkmark")
                    } else {
                        Text(playlist.name)
                    }
                }
            }
            Divider()
            Button("Add playlist…") { isAdding = true }
            Button("Reload player") { player.reload() }
            if let selected = player.selectedPlaylist {
                Button("Remove “\(selected.name)”", role: .destructive) { player.removeSelectedPlaylist() }
            }
        } label: {
            HStack(spacing: 3) {
                Text(player.selectedPlaylist?.name ?? "Playlists")
                    .font(TypeScale.meta)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch playlist")
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a playlist")
                .font(TypeScale.title)
            InputWell(systemImage: "link", placeholder: "YouTube playlist link", text: $newLink)
            InputWell(systemImage: "textformat", placeholder: "Name (uses the YouTube title if empty)", text: $newName, onSubmit: add)
            Text(addError ?? "The playlist must be Public or Unlisted. Private playlists can't play outside YouTube.")
                .font(TypeScale.meta)
                .foregroundStyle(addError == nil ? Color.secondary : Theme.ember)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Cancel") { resetForm() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Add playlist", action: add)
                    .buttonStyle(EmberButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(newLink.isEmpty)
            }
        }
    }

    private func add() {
        if let error = player.addPlaylist(link: newLink, name: newName) {
            addError = error
        } else {
            resetForm()
        }
    }

    private func resetForm() {
        isAdding = false
        newLink = ""
        newName = ""
        addError = nil
    }
}

/// Shows the player's video in the popover by borrowing the app-owned web view; it goes
/// back to the invisible window when video mode is switched off or the details collapse.
private struct VideoSurface: NSViewRepresentable {
    let player: FocusPlayer

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        player.showVideo(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        player.showVideo(in: container)
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.player.hideVideo(from: container)
    }

    func makeCoordinator() -> Coordinator { Coordinator(player: player) }

    final class Coordinator {
        let player: FocusPlayer
        init(player: FocusPlayer) { self.player = player }
    }
}

private struct Artwork: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.washStrong)
            Image(systemName: "music.note")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ember)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Hairline playback progress under the collapsed strip.
private struct ThinProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.wash)
                Capsule().fill(Theme.amber).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 2)
    }
}

/// Progress bar you can click or drag to seek.
private struct ProgressScrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    private var fraction: Double {
        dragFraction ?? (duration > 0 ? min(1, position / duration) : 0)
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.wash).frame(height: 4)
                    Capsule().fill(Theme.amber).frame(width: max(4, geometry.size.width * fraction), height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(1, max(0, $0.location.x / geometry.size.width)) }
                        .onEnded { value in
                            onSeek(min(1, max(0, value.location.x / geometry.size.width)))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 12)
            .disabled(duration <= 0)
            HStack {
                Text(Format.clock(duration > 0 ? fraction * duration : 0))
                Spacer()
                Text(Format.clock(duration))
            }
            .font(TypeScale.meta.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
