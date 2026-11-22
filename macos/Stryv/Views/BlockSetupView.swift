import StryvCore
import SwiftUI

/// Choosing how long to lock in and what to block, then committing.
struct BlockSetupView: View {
    @EnvironmentObject private var model: BlockModel
    @State private var siteDraft = ""
    @State private var isEditingSites = false
    @State private var isConfirming = false
    @FocusState private var durationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            duration
            sites
            commit
        }
        .onChange(of: model.durationText) { isConfirming = false }
        .onChange(of: model.blocklist) { isConfirming = false }
    }

    // MARK: Duration (the hero: you type how long you're committing)

    private var duration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Focus for")
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                Spacer()
                endsHint
            }
            TextField("2m, 45m, 1h 30m", text: $model.durationText)
                .textFieldStyle(.plain)
                .font(TypeScale.numerals())
                .foregroundStyle(model.durationMinutes == nil && !model.durationText.isEmpty ? Theme.ember : Color.primary)
                .focused($durationFocused)
                .padding(.vertical, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(durationFocused ? Theme.ember : Theme.hairline)
                        .frame(height: durationFocused ? 2 : 1)
                        .offset(y: 4)
                }
                .help("Type any length from 1 minute to 24 hours, like 2m, 45 min, 1h 30m or 1:30.")
            FlowLayout(spacing: 2, lineSpacing: 4) {
                ForEach(BlockModel.presetMinutes, id: \.self) { minutes in
                    PresetButton(title: Format.duration(minutes: minutes), isSelected: !model.isRestOfDay && model.durationMinutes == minutes) {
                        model.selectPreset(minutes)
                    }
                }
                PresetButton(title: BlockModel.restOfDayLabel, isSelected: false) {
                    model.selectRestOfDay()
                }
                .help("Fill in the time left until midnight")
            }
            .padding(.leading, -7)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var endsHint: some View {
        if let minutes = model.durationMinutes {
            TimelineView(.everyMinute) { context in
                Text("Ends at \(Format.endTime(context.date.addingTimeInterval(TimeInterval(minutes * 60))))")
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
            }
        } else if !model.durationText.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Try 2m, 45m or 1h 30m")
                .font(TypeScale.meta)
                .foregroundStyle(Theme.ember)
        }
    }

    // MARK: Sites (collapsed to one line until you edit them)

    private var sites: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !model.blocklist.isEmpty {
                    SiteStack(domains: model.blocklist)
                }
                Text(sitesSummary)
                    .font(TypeScale.body)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isEditingSites.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text(isEditingSites ? "Done" : "Edit")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isEditingSites ? 180 : 0))
                    }
                }
                .buttonStyle(TextActionStyle())
            }
            if isEditingSites || model.blocklist.isEmpty {
                InputWell(systemImage: "plus", placeholder: "Add a site, like youtube.com", text: $siteDraft, onSubmit: addSite)
                if !model.blocklist.isEmpty {
                    FlowLayout {
                        ForEach(model.blocklist, id: \.self) { domain in
                            SiteChip(domain: domain) { model.removeFromBlocklist(domain) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sitesSummary: String {
        switch model.blocklist.count {
        case 0: "No sites to block yet"
        case 1: "1 site blocked"
        default: "\(model.blocklist.count) sites blocked"
        }
    }

    // MARK: Commit

    @ViewBuilder
    private var commit: some View {
        if isConfirming, let minutes = model.durationMinutes {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isRestOfDay
                        ? "Lock in until midnight?"
                        : "Lock in for \(Format.spokenDuration(minutes: minutes))?")
                        .font(TypeScale.title)
                    Text("\(sitesSummary.prefix(1).uppercased() + sitesSummary.dropFirst()) until \(Format.endTime(Date().addingTimeInterval(TimeInterval(minutes * 60)))). Nothing in Stryv can end it early, not even quitting or restarting your Mac.")
                        .font(TypeScale.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("Cancel") { isConfirming = false }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Lock in") {
                        isConfirming = false
                        Task { await model.startBlock() }
                    }
                    .buttonStyle(EmberButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .transition(.opacity)
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isConfirming = true }
            } label: {
                Text(commitTitle)
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(!model.canStartBlock)
        }
    }

    private var commitTitle: String {
        if model.isWorking { return "Locking in…" }
        guard let minutes = model.durationMinutes else { return "Lock in" }
        if model.isRestOfDay { return "Lock in until midnight" }
        return "Lock in for \(Format.duration(minutes: minutes))"
    }

    private func addSite() {
        guard !siteDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if model.addToBlocklist(siteDraft) { siteDraft = "" }
    }
}
