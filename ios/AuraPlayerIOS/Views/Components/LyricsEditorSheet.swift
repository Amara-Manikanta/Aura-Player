import SwiftUI

/// Write or fix a song's lyrics, then sync them: play the song and tap once as each line starts.
public struct LyricsEditorSheet: View {
    /// The song being edited stays the one the sheet opened for, even if the player moves on
    @State private var pinned: MediaTrack
    private var track: MediaTrack { pinned }
    @ObservedObject var playback: PlaybackManager
    @Environment(\.dismiss) private var dismiss

    private enum Step: String, CaseIterable { case write = "Write", sync = "Sync" }
    @State private var step: Step = .write
    @State private var text: String = ""
    @State private var times: [Double?] = []
    @State private var selected: Int = 0
    @State private var hadCustom: Bool = false
    @FocusState private var editing: Bool

    public init(track: MediaTrack, playback: PlaybackManager) {
        _pinned = State(initialValue: track)
        self.playback = playback
    }

    /// One lyric per non-empty line
    private var lines: [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var syncedCount: Int { times.prefix(lines.count).compactMap { $0 }.count }

    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                VStack(spacing: 12) {
                    Picker("", selection: $step) {
                        ForEach(Step.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    if step == .write { writeStep } else { syncStep }
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(AuraTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AuraTheme.primary)
                        .disabled(lines.isEmpty)
                }
            }
            .onAppear { playback.holdForLyricsEditor = true; load() }
            .onDisappear { playback.holdForLyricsEditor = false }
            .onChange(of: step) { _, new in
                if new == .sync { editing = false; prepareSync() }
            }
        }
    }

    // MARK: - Write

    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(track.title) • \(track.artist)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AuraTheme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 20)

            TextEditor(text: $text)
                .focused($editing)
                .scrollContentBackground(.hidden)
                .foregroundColor(AuraTheme.textPrimary)
                .font(.system(size: 16))
                .padding(10)
                .liquidGlass(cornerRadius: 16)
                .padding(.horizontal, 16)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type or paste the lyrics, one line per lyric.\nLyrics with [mm:ss] times (LRC) keep their timing.")
                            .font(.system(size: 15))
                            .foregroundColor(AuraTheme.textTertiary)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    if let pasted = strings.first { setText(from: pasted) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(AuraTheme.primary)

                Button {
                    copyLRC()
                    Haptics.light()
                } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 20) }
                .buttonBorderShape(.capsule)
                .buttonStyle(.bordered)
                .tint(AuraTheme.primary)
                .disabled(lines.isEmpty)

                Text("\(lines.count) lines")
                    .font(.system(size: 13))
                    .foregroundColor(AuraTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()

                Spacer()

                Button {
                    Haptics.light()
                    editing = false
                    prepareSync()
                    step = .sync
                } label: {
                    Label("Sync Lines", systemImage: "timer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AuraTheme.primaryGradient, in: Capsule())
                }
                .disabled(lines.isEmpty)
                .opacity(lines.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Sync

    private var syncStep: some View {
        VStack(spacing: 10) {
            Text(syncedCount == lines.count ? "All \(lines.count) lines synced. Tap a line to fine-tune it."
                 : "Play the song, then tap the big button right as each highlighted line begins.")
                .font(.system(size: 13))
                .foregroundColor(AuraTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            lineRow(i, line)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .onChange(of: selected) { _, new in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
                }
            }

            controls
        }
    }

    private func lineRow(_ i: Int, _ line: String) -> some View {
        let isSelected = i == selected
        let time = i < times.count ? times[i] : nil
        return Button {
            selected = i
            if let time { playback.seek(to: max(0, time - 1)) }
        } label: {
            HStack(spacing: 10) {
                Text(time.map(format) ?? "--:--")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(time == nil ? AuraTheme.textTertiary : AuraTheme.primary)
                    .frame(width: 52, alignment: .leading)
                Text(line)
                    .font(.system(size: isSelected ? 17 : 15, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? AuraTheme.textPrimary : AuraTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? Color.white.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // the line being timed, and where the song is
            ClockObserver(playback.clock) { time in
                HStack {
                    Text(format(time))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(AuraTheme.textSecondary)
                    Spacer()
                    Text("Line \(min(selected + 1, max(lines.count, 1))) of \(lines.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AuraTheme.textSecondary)
                }
            }
            .padding(.horizontal, 24)

            Button {
                markLine()
            } label: {
                VStack(spacing: 2) {
                    Text(selected < lines.count ? "TAP: this line starts now" : "All lines marked")
                        .font(.system(size: 16, weight: .heavy))
                    if selected < lines.count {
                        Text(lines[selected])
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(AuraTheme.primaryGradient, in: RoundedRectangle(cornerRadius: 20))
            }
            .disabled(selected >= lines.count)
            .opacity(selected >= lines.count ? 0.5 : 1)
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                smallButton("gobackward.5", "5s") { playback.seek(to: max(0, playback.currentTime - 5)) }
                smallButton(playback.isPlaying ? "pause.fill" : "play.fill", playback.isPlaying ? "Pause" : "Play") { playback.togglePlayPause() }
                smallButton("arrow.uturn.backward", "Undo") { undo() }
                smallButton("minus", "0.5s") { nudge(-0.5) }
                smallButton("plus", "0.5s") { nudge(0.5) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func smallButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(AuraTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func load() {
        if let custom = CustomLyricsStore.shared.entry(for: track) {
            hadCustom = true
            text = custom.lines.joined(separator: "\n")
            times = custom.times
        } else if let online = playback.lyrics {
            // Start from the lyrics found online, so wrong lines or timing can be fixed
            if online.isSynced {
                text = online.syncedLines.map(\.text).joined(separator: "\n")
                times = online.syncedLines.map { Optional($0.time) }
            } else if let plain = online.plainLyrics {
                text = plain
            }
        }
        step = lines.isEmpty ? .write : step
        if lines.isEmpty { editing = true }
    }


    /// The lyrics as LRC text ("[01:23.45] words"), so they can be pasted into another song with their times
    private func copyLRC() {
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            if i < times.count, let t = times[i] {
                out.append(String(format: "[%02d:%05.2f] %@", Int(t) / 60, t.truncatingRemainder(dividingBy: 60), line))
            } else { out.append(line) }
        }
        UIPasteboard.general.string = out.joined(separator: "\n")
    }

    /// Reads pasted text: LRC keeps its times
    private func setText(from pasted: String) {
        let entry = CustomLyricsStore.parse(pasted)
        text = entry.lines.joined(separator: "\n")
        times = entry.times
        selected = 0
    }

    /// Times belong to lines by position, so if lines were added or removed they no longer match: start the timing again
    private func prepareSync() {
        let count = lines.count
        if times.count != count { times = Array(repeating: nil, count: count) }
        selected = times.firstIndex(where: { $0 == nil }) ?? 0
    }

    private func markLine() {
        guard selected < lines.count else { return }
        Haptics.medium()
        while times.count < lines.count { times.append(nil) }
        times[selected] = playback.currentTime
        selected = min(selected + 1, lines.count)
    }

    /// Takes back the last mark and replays from just before it
    private func undo() {
        let target = selected >= lines.count ? lines.count - 1 : max(selected - 1, 0)
        guard target >= 0, target < times.count else { return }
        let was = times[target]
        times[target] = nil
        selected = target
        if let was { playback.seek(to: max(0, was - 3)) }
    }

    /// Moves the selected line's time a little earlier / later
    private func nudge(_ delta: Double) {
        let i = min(selected, lines.count - 1)
        guard i >= 0, i < times.count, let t = times[i] else { return }
        times[i] = max(0, t + delta)
        playback.seek(to: max(0, times[i]! - 1))
    }

    private func save() {
        let all = lines
        var saved = times
        if saved.count < all.count { saved += Array(repeating: nil, count: all.count - saved.count) }
        saved = Array(saved.prefix(all.count))
        CustomLyricsStore.shared.save(.init(lines: all, times: saved), for: track)
        playback.reloadLyrics()
        Haptics.success()
        dismiss()
    }

    private func format(_ t: Double) -> String {
        let s = max(0, t)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}
