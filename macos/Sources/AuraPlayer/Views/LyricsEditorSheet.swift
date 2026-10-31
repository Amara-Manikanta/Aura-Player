import SwiftUI
import AppKit

/// Write or fix a song's lyrics, then sync them: play the song and press Return (or click the big button) as each line starts.
struct LyricsEditorSheet: View {
    /// The song being edited stays the one the sheet opened for, even if the player moves on
    @State private var pinned: MediaTrack
    private var track: MediaTrack { pinned }
    @Bindable var playback: PlaybackManager
    
    init(track: MediaTrack, playback: PlaybackManager) {
        _pinned = State(initialValue: track)
        self.playback = playback
    }
    @Environment(\.dismiss) private var dismiss
    
    private enum Step: String, CaseIterable { case write = "Write", sync = "Sync" }
    @State private var step: Step = .write
    @State private var text: String = ""
    @State private var times: [Double?] = []
    @State private var selected: Int = 0
    @State private var hadCustom = false
    
    /// One lyric per non-empty line
    private var lines: [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var syncedCount: Int { times.prefix(lines.count).compactMap { $0 }.count }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Lyrics")
                    .font(.title3.bold())
                Text("\(track.title) • \(track.artist)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Picker("", selection: $step) {
                    ForEach(Step.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            
            if step == .write { writeStep } else { syncStep }
            
            Divider()
            HStack {
                if hadCustom {
                    Button("Remove My Lyrics", role: .destructive) {
                        CustomLyricsFile.remove(title: track.title, artist: track.artist)
                        playback.reloadLyrics()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(lines.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
        .onAppear { playback.holdForLyricsEditor = true; load() }
        .onDisappear { playback.holdForLyricsEditor = false }
        .onChange(of: step) { _, new in if new == .sync { prepareSync() } }
    }
    
    // MARK: - Write
    
    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type or paste the lyrics, one line per lyric.\nLyrics with [mm:ss] times (LRC) keep their timing.")
                            .foregroundStyle(.tertiary)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
            
            HStack {
                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string) { setText(from: pasted) }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Button {
                    copyLRC()
                } label: { Label("Copy with Times", systemImage: "doc.on.doc") }
                .disabled(lines.isEmpty)
                Text("\(lines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    prepareSync()
                    step = .sync
                } label: { Label("Sync Lines", systemImage: "timer") }
                .disabled(lines.isEmpty)
            }
        }
    }
    
    // MARK: - Sync
    
    private var syncStep: some View {
        VStack(spacing: 10) {
            Text(syncedCount == lines.count ? "All \(lines.count) lines synced. Click a line to fine-tune it."
                 : "Play the song, then press Return (or click the big button) right as each highlighted line begins.")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            lineRow(i, line).id(i)
                        }
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: selected) { _, new in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            
            HStack {
                Text(format(playback.currentTime))
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                Text("Line \(min(selected + 1, max(lines.count, 1))) of \(lines.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                markLine()
            } label: {
                VStack(spacing: 2) {
                    Text(selected < lines.count ? "This line starts now  ⏎" : "All lines marked")
                        .font(.headline)
                    if selected < lines.count {
                        Text(lines[selected]).font(.caption).lineLimit(1).opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selected >= lines.count)
            
            HStack(spacing: 8) {
                Button { playback.seek(to: max(0, playback.currentTime - 5)) } label: { Label("−5s", systemImage: "gobackward.5") }
                Button { playback.togglePlayPause() } label: {
                    Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                Spacer()
                Button { nudge(-0.5) } label: { Label("0.5s", systemImage: "minus") }
                    .help("Move the selected line 0.5 s earlier")
                Button { nudge(0.5) } label: { Label("0.5s", systemImage: "plus") }
                    .help("Move the selected line 0.5 s later")
            }
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
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(time == nil ? Color.secondary : Color.purple)
                    .frame(width: 52, alignment: .leading)
                Text(line)
                    .font(.system(size: isSelected ? 15 : 13, weight: isSelected ? .bold : .regular))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func load() {
        if let custom = CustomLyricsFile.entry(title: track.title, artist: track.artist) {
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
        if !lines.isEmpty { step = .write }
    }
    

    /// The lyrics as LRC text ("[01:23.45] words"), so they can be pasted into another song with their times
    private func copyLRC() {
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            if i < times.count, let t = times[i] {
                out.append(String(format: "[%02d:%05.2f] %@", Int(t) / 60, t.truncatingRemainder(dividingBy: 60), line))
            } else { out.append(line) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.joined(separator: "\n"), forType: .string)
    }

    private func setText(from pasted: String) {
        let entry = CustomLyricsFile.parse(pasted)
        text = entry.lines.joined(separator: "\n")
        times = entry.times
        selected = 0
    }
    
    /// Times belong to lines by position, so if lines were added or removed they no longer match: start the timing again
    private func prepareSync() {
        if times.count != lines.count { times = Array(repeating: nil, count: lines.count) }
        selected = times.firstIndex(where: { $0 == nil }) ?? 0
    }
    
    private func markLine() {
        guard selected < lines.count else { return }
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
    
    private func nudge(_ delta: Double) {
        let i = min(selected, lines.count - 1)
        guard i >= 0, i < times.count, let t = times[i] else { return }
        times[i] = max(0, t + delta)
        playback.seek(to: max(0, (times[i] ?? 0) - 1))
    }
    
    private func save() {
        let all = lines
        var saved = times
        if saved.count < all.count { saved += Array(repeating: nil, count: all.count - saved.count) }
        saved = Array(saved.prefix(all.count))
        CustomLyricsFile.save(.init(lines: all, times: saved, modified: nil), title: track.title, artist: track.artist)
        playback.reloadLyrics()
        dismiss()
    }
    
    private func format(_ t: Double) -> String {
        let s = max(0, t)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}
