import SwiftUI
import UIKit

/// "•••" options for the song that's playing now, like the Mac app: start/end time, video, playlists.
/// Shown on the mini player.
public struct CurrentSongMenu: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var store: PlaylistStore
    var iconColor: Color = AuraTheme.textSecondary

    @State private var showTrimSheet = false
    @State private var showVideoSheet = false
    @State private var showAddSheet = false
    @State private var showLyricsSheet = false
    @State private var notice: String?
    @State private var showRename = false
    @State private var newTitle = ""
    @State private var newArtist = ""

    public init(playback: PlaybackManager, store: PlaylistStore = .shared, iconColor: Color = AuraTheme.textSecondary) {
        self.playback = playback
        self.store = store
        self.iconColor = iconColor
    }

    /// "Song Title – Artist" (just the title when the artist is unknown)
    static func nameToCopy(_ track: MediaTrack) -> String {
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        return artist.isEmpty || artist == "Unknown Artist" ? track.title : "\(track.title) – \(artist)"
    }

    public var body: some View {
        Menu {
            if let track = playback.currentTrack {
                Button {
                    UIPasteboard.general.string = Self.nameToCopy(track)
                    Haptics.light()
                } label: { Label("Copy Song Name", systemImage: "doc.on.doc") }
                Button {
                    newTitle = track.title
                    newArtist = track.artist
                    showRename = true
                } label: { Label("Rename Song…", systemImage: "pencil") }
                trimSection(track)
                Button { showLyricsSheet = true } label: {
                    Label(CustomLyricsStore.shared.hasLyrics(for: track) ? "Edit My Lyrics…" : "Add / Sync Lyrics…", systemImage: "text.quote")
                }
                if track.sourceType == .youtube { videoSection(track) }
                playlistSection(track)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .disabled(playback.currentTrack == nil)
        .sheet(isPresented: $showTrimSheet) {
            if let track = playback.currentTrack { TrimTimesSheet(track: track, store: store, playback: playback) }
        }
        .sheet(isPresented: $showVideoSheet) {
            if let track = playback.currentTrack { ChangeVideoLinkSheet(track: track, store: store, playback: playback) }
        }
        .sheet(isPresented: $showLyricsSheet) {
            if let track = playback.currentTrack { LyricsEditorSheet(track: track, playback: playback) }
        }
        .sheet(isPresented: $showAddSheet) {
            if let track = playback.currentTrack { AddToPlaylistSheet(track: track, playlistStore: store) }
        }
        .alert("Rename Song", isPresented: $showRename) {
            TextField("Song name", text: $newTitle)
            TextField("Artist", text: $newArtist)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
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
        Section(track.trimLabel.map { "Plays \($0)" } ?? "Start & End Time") {
            Button {
                let now = playback.currentTime
                // keep the end only if it's still after the new start
                let end = (track.endTime ?? 0) > now + 1 ? track.endTime : nil
                setTrim(track, start: now, end: end)
            } label: { Label("Start From Current Position", systemImage: "arrow.right.to.line") }
            Button {
                let now = playback.currentTime
                let start = (track.startTime ?? 0) < now - 1 ? track.startTime : nil
                setTrim(track, start: start, end: now)
            } label: { Label("End at Current Position", systemImage: "arrow.left.to.line") }
            Button { showTrimSheet = true } label: { Label("Set Start & End Time…", systemImage: "scissors") }
            if track.trimLabel != nil {
                Button { setTrim(track, start: nil, end: nil) } label: { Label("Clear Start & End Time", systemImage: "xmark.circle") }
            }
        }
    }

    @ViewBuilder
    private func videoSection(_ track: MediaTrack) -> some View {
        Section("Video") {
            Button { playback.confirmCurrentVideo() } label: { Label("Right Video (always play it)", systemImage: "hand.thumbsup") }
            Button { playback.rejectCurrentVideo() } label: { Label("Wrong Video (try the next best)", systemImage: "hand.thumbsdown") }
            Button { showVideoSheet = true } label: { Label("Change Video Link…", systemImage: "link") }
            if let id = track.youtubeId, let url = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                Button { UIApplication.shared.open(url) } label: { Label("Open in YouTube", systemImage: "play.rectangle") }
                Button { UIPasteboard.general.string = url.absoluteString } label: { Label("Copy YouTube Link", systemImage: "doc.on.doc") }
            }
        }
    }

    @ViewBuilder
    private func playlistSection(_ track: MediaTrack) -> some View {
        Section("Playlists") {
            let isFav = store.isTrackFavorite(track)
            Button { store.toggleFavorite(track: track) } label: {
                Label(isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: isFav ? "heart.slash" : "heart")
            }
            Button { showAddSheet = true } label: { Label("Add to Playlist…", systemImage: "text.badge.plus") }
            let containing = store.playlists.filter { pl in !pl.isBuiltIn && pl.tracks.contains { $0.id == track.id } }
            if !containing.isEmpty {
                Menu {
                    ForEach(containing) { pl in
                        Button(pl.name.trimmingCharacters(in: .whitespaces), role: .destructive) {
                            store.removeTrack(trackId: track.id, from: pl.id)
                            notice = "Removed from \(pl.name.trimmingCharacters(in: .whitespaces))."
                        }
                    }
                } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
            }
        }
    }

    private func rename() {
        guard let track = playback.currentTrack else { return }
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let artist = newArtist.trimmingCharacters(in: .whitespaces)
        let finalArtist = artist.isEmpty ? "Unknown Artist" : artist
        store.renameSong(track, title: title, artist: finalArtist)
        playback.currentTrack?.title = title
        playback.currentTrack?.artist = finalArtist
        playback.updateNowPlayingInfo()
        Haptics.success()
    }

    private func setTrim(_ track: MediaTrack, start: Double?, end: Double?) {
        store.setTrimTimes(for: track, start: start, end: end)
        playback.currentTrack?.startTime = (start ?? 0) > 0 ? start : nil
        playback.currentTrack?.endTime = end
        Haptics.light()
    }
}
