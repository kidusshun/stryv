import StryvCore
import SwiftUI

/// The running block: the countdown and its burning fuse, then what's blocked. There is
/// intentionally no way to stop it here.
struct ActiveBlockView: View {
    @EnvironmentObject private var model: BlockModel
    let block: BlockState
    @State private var draft = ""
    @State private var isAdding = false
    @State private var showsSites = false

    private var remaining: TimeInterval { block.remaining(at: model.now) }
    private var progress: Double { min(1, max(0, 1 - remaining / block.totalDuration)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Format.countdown(remaining))
                    .font(TypeScale.numerals(44))
                    .foregroundStyle(Theme.ember)
                    .shadow(color: Theme.ember.opacity(0.35), radius: 14)
                    .contentTransition(.numericText(countsDown: true))
                Fuse(progress: progress)
                HStack {
                    Text("Started \(Format.endTime(block.startedAt))")
                    Spacer()
                    Text("Ends \(Format.endTime(block.endsAt))")
                }
                .font(TypeScale.meta)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SiteStack(domains: block.domains)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showsSites.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(block.domains.count == 1 ? "1 site blocked" : "\(block.domains.count) sites blocked")
                                .font(TypeScale.body)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsSites ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(isAdding ? "Done" : "Add site") {
                        withAnimation(.easeOut(duration: 0.2)) { isAdding.toggle() }
                    }
                    .buttonStyle(TextActionStyle())
                }
                if showsSites {
                    FlowLayout {
                        ForEach(block.domains, id: \.self) { SiteChip(domain: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isAdding {
                    InputWell(systemImage: "plus", placeholder: "Add a site to this block", text: $draft, onSubmit: add) {
                        if model.isWorking { ProgressView().controlSize(.small) }
                    }
                }
            }

            Text("You can add sites, but nothing ends this block early.")
                .font(TypeScale.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        let input = draft
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            if await model.addToActiveBlock(input) { draft = "" }
        }
    }
}
