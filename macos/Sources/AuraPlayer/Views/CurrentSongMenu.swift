import SwiftUI
import AppKit

/// "•••" options for the song that's playing now: start/end time, video, playlists, favourites, feedback.
/// Shown on Now Playing, in the player bar and in the mini player.
public struct CurrentSongMenu: View {
    @Bindable var playback: PlaybackManager
    var iconColor: Color = .secondary
    var iconSize: CGFloat = 14
    
    @State private var showTrimSheet = false
    @State private var showVideoSheet = false
    @State private var notice: String?
    
    public init(playback: PlaybackManager, iconColor: Color = .secondary, iconSize: CGFloat = 14) {
        self.playback = playback
        self.iconColor = iconColor
        self.iconSize = iconSize
    }
    
    private var track: MediaTrack? { playback.currentTrack }
    private var store: PlaylistStore? { playback.playlistStore }
    
    public var body: some View {
        Menu {
            if let track {
                trimSection(track)
                Divider()
                if track.sourceType == .youtube { videoSection(track) ; Divider() }
                playlistSection(track)
            } else {
                Text("Nothing playing")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options for this song")
        .disabled(track == nil)
        .sheet(isPresented: $showTrimSheet) {
            if let track, let store { TrimTimesSheet(track: track, store: store, playback: playback) }
        }
        .sheet(isPresented: $showVideoSheet) {
            if let track, let store { ChangeVideoLinkSheet(track: track, store: store, playback: playback) }
        }
        .alert("Song Options", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private func trimSection(_ track: MediaTrack) -> some View {
        // No live time in these labels: anything that changes while the menu is open makes macOS close it.
        // The position is read at the moment you click.
        Section(track.trimLabel.map { "Plays \($0)" } ?? "Start & End Time") {
            Button("Start From Current Position") {
                let now = playback.currentTime
                // keep the end only if it's still after the new start
                let end = (track.endTime ?? 0) > now + 1 ? track.endTime : nil
                setTrim(track, start: now, end: end)
            }
            Button("End at Current Position") {
                let now = playback.currentTime
                let start = (track.startTime ?? 0) < now - 1 ? track.startTime : nil
                setTrim(track, start: start, end: now)
            }
            Button("Set Start & End Time…") { showTrimSheet = true }
            if track.trimLabel != nil {
                Button("Clear Start & End Time") { setTrim(track, start: nil, end: nil) }
            }
        }
    }
    
    @ViewBuilder
    private func videoSection(_ track: MediaTrack) -> some View {
        Section("Video") {
            Button("Right Video 👍 (always play it)") { playback.confirmCurrentVideo() }
            Button("Wrong Video 👎 (try the next best)") { playback.rejectCurrentVideo() }
            Button("Change Video Link…") { showVideoSheet = true }
            if let id = track.youtubeId {
                Button("Open on YouTube") {
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { NSWorkspace.shared.open(url) }
                }
                Button("Copy YouTube Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://www.youtube.com/watch?v=\(id)", forType: .string)
                }
            }
        }
    }
    
    @ViewBuilder
    private func playlistSection(_ track: MediaTrack) -> some View {
        if let store {
            Section("Playlists") {
                Button(store.isFavorite(track: track) ? "Remove from Favorites" : "Add to Favorites") {
                    store.toggleFavorite(track: track)
                }
                Menu("Add to Playlist") {
                    ForEach(store.playlists.filter { !$0.isBuiltIn }) { pl in
                        Button(pl.name.trimmingCharacters(in: .whitespaces)) { add(track, to: pl, store: store) }
                    }
                }
                let containing = store.playlists.filter { pl in pl.tracks.contains { $0.id == track.id } }
                if !containing.isEmpty {
                    Menu("Remove from Playlist") {
                        ForEach(containing) { pl in
                            Button(pl.name.trimmingCharacters(in: .whitespaces)) {
                                store.removeTrack(trackId: track.id, from: pl.id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func setTrim(_ track: MediaTrack, start: Double?, end: Double?) {
        store?.setTrimTimes(for: track, start: start, end: end)
        playback.applyTrim(to: track.id, start: start, end: end)
        AppLog.log("trim", "\"\(track.title)\" start=\(start.map { "\(Int($0))s" } ?? "-") end=\(end.map { "\(Int($0))s" } ?? "-") (from player)")
    }
    
    private func add(_ track: MediaTrack, to playlist: Playlist, store: PlaylistStore) {
        let name = playlist.name.trimmingCharacters(in: .whitespaces)
        if store.savedSongs(matching: track).contains(where: { $0.playlist.id == playlist.id }) {
            notice = "\"\(track.title)\" is already in \(name)."
        } else {
            store.addTrack(track, to: playlist.id)
            notice = "Added to \(name)."
        }
    }
    
    static func format(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
