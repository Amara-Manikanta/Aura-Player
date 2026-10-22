import SwiftUI

/// Lets the user choose where a song starts and stops (e.g. skip a long intro or outro).
public struct TrimTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let track: MediaTrack
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    @State private var startText: String
    @State private var endText: String
    @State private var errorText: String?
    
    public init(track: MediaTrack, store: PlaylistStore, playback: PlaybackManager) {
        self.track = track
        self.store = store
        self.playback = playback
        _startText = State(initialValue: track.startTime.map(Self.format) ?? "")
        _endText = State(initialValue: track.endTime.map(Self.format) ?? "")
    }
    
    private var isPlayingThis: Bool { playback.currentTrack?.id == track.id }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.title3)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start & End Time").font(.title3.bold())
                    Text(track.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            
            timeRow(label: "Start at", text: $startText, placeholder: "0:00")
            timeRow(label: "End at", text: $endText, placeholder: track.duration > 0 ? Self.format(track.duration) : "end")
            
            Text("Use minutes:seconds, like 0:15 or 3:40. Leave End empty to play to the end.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
            
            HStack {
                Button("Clear") {
                    save(start: nil, end: nil)
                }
                .disabled(track.startTime == nil && track.endTime == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { validateAndSave() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    private func timeRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            if isPlayingThis {
                Button("Use current position") {
                    text.wrappedValue = Self.format(playback.currentTime)
                }
                .font(.caption)
            }
        }
    }
    
    private func validateAndSave() {
        let start = Self.parse(startText)
        let end = Self.parse(endText)
        if !startText.trimmingCharacters(in: .whitespaces).isEmpty && start == nil {
            errorText = "Start time should look like 0:15"
            return
        }
        if !endText.trimmingCharacters(in: .whitespaces).isEmpty && end == nil {
            errorText = "End time should look like 3:40"
            return
        }
        if let s = start, let e = end, e <= s + 1 {
            errorText = "End time must be after the start time"
            return
        }
        if let e = end, track.duration > 0, e > track.duration + 1 {
            errorText = "End time is past the end of the song (\(Self.format(track.duration)))"
            return
        }
        save(start: start, end: end)
    }
    
    private func save(start: Double?, end: Double?) {
        store.setTrimTimes(for: track, start: start, end: end)
        playback.applyTrim(to: track.id, start: start, end: end)
        AppLog.log("trim", "\"\(track.title)\" start=\(start.map { "\(Int($0))s" } ?? "-") end=\(end.map { "\(Int($0))s" } ?? "-")")
        dismiss()
    }
    
    static func format(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    
    /// "1:05", "65" or "1:05.5" → seconds
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":").map(String.init)
        switch parts.count {
        case 1: return Double(parts[0])
        case 2:
            guard let m = Double(parts[0]), let s = Double(parts[1]), s < 60 else { return nil }
            return m * 60 + s
        case 3:
            guard let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
            return h * 3600 + m * 60 + s
        default: return nil
        }
    }
}
