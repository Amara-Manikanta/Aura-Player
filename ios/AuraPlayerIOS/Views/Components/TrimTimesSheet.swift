import SwiftUI

public struct TrimTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let track: MediaTrack
    @ObservedObject var store: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
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
        NavigationStack {
            ZStack {
                AuraBackground()
                
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "scissors")
                            .font(.system(size: 24))
                            .foregroundColor(AuraTheme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trim Start & End Time")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                            Text(track.title)
                                .font(.system(size: 13))
                                .foregroundColor(AuraTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 16)
                    
                    VStack(spacing: 14) {
                        timeRow(label: "Start at", text: $startText, placeholder: "0:00")
                        timeRow(label: "End at", text: $endText, placeholder: track.duration > 0 ? Self.format(track.duration) : "End")
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16)
                    
                    Text("Skip intros or speech. Use min:sec format (e.g. 0:25 or 3:40). Leave End empty to play to completion.")
                        .font(.system(size: 13))
                        .foregroundColor(AuraTheme.textTertiary)
                    
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button("Clear") {
                            save(start: nil, end: nil)
                        }
                        .foregroundColor(AuraTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .liquidGlass(cornerRadius: 14)
                        
                        Button("Save Trim") {
                            validateAndSave()
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AuraTheme.primaryGradient)
                        .cornerRadius(14)
                        .font(.system(size: 16, weight: .bold))
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Trim Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AuraTheme.textSecondary)
                }
            }
        }
    }
    
    private func timeRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AuraTheme.textPrimary)
                .frame(width: 80, alignment: .leading)
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(10)
                .liquidGlass(cornerRadius: 10)
                .foregroundColor(AuraTheme.textPrimary)
                .frame(width: 100)
            
            Spacer()
            
            if isPlayingThis {
                Button("Current") {
                    text.wrappedValue = Self.format(playback.currentTime)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AuraTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AuraTheme.primary.opacity(0.15))
                .cornerRadius(8)
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
            errorText = "End time must be after start time"
            return
        }
        save(start: start, end: end)
    }
    
    private func save(start: Double?, end: Double?) {
        // (used to edit the playlists without saving, so trims were lost on restart)
        store.setTrimTimes(for: track, start: start, end: end)
        if playback.currentTrack?.id == track.id {
            playback.currentTrack?.startTime = start
            playback.currentTrack?.endTime = end
        }
        Haptics.success()
        dismiss()
    }
    
    static func format(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    
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
