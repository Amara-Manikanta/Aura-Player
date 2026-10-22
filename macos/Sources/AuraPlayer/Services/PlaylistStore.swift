import Foundation
import Observation
import AppKit

public struct ArtistGroup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let trackCount: Int
    public let totalPlayCount: Int
    public let tracks: [MediaTrack]
    public let sampleArtworkURL: String?
}

@MainActor
@Observable
public final class PlaylistStore {
    public var playlists: [Playlist] = []
    public var favoritesPlaylistId: UUID
    public var localLibraryPlaylistId: UUID
    
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AuraPlayer", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("playlists.json")
        
        let favId = UUID()
        let localId = UUID()
        self.favoritesPlaylistId = favId
        self.localLibraryPlaylistId = localId
        
        load()
    }
    
    public var favoritesPlaylist: Playlist? {
        playlists.first { $0.id == favoritesPlaylistId }
    }
    
    public var localLibraryPlaylist: Playlist? {
        playlists.first { $0.id == localLibraryPlaylistId }
    }
    
    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data),
              !decoded.isEmpty else {
            setupDefaults()
            return
        }
        
        self.playlists = decoded
        
        // Repair playlists saved by earlier merges that contain the same track ID twice
        var repaired = false
        for i in playlists.indices {
            let fixed = Self.uniquingTrackIds(playlists[i].tracks)
            if fixed.map(\.id) != playlists[i].tracks.map(\.id) {
                playlists[i].tracks = fixed
                repaired = true
            }
        }
        if repaired { save() }
        
        if let fav = playlists.first(where: { $0.name == "Favorites" }) {
            self.favoritesPlaylistId = fav.id
        }
        if let local = playlists.first(where: { $0.name == "Local Library" }) {
            self.localLibraryPlaylistId = local.id
        }
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    /// SwiftUI's List crashes when a ForEach contains duplicate IDs, so give repeated tracks a fresh ID.
    private static func uniquingTrackIds(_ tracks: [MediaTrack]) -> [MediaTrack] {
        var seen = Set<UUID>()
        return tracks.map { track in
            if seen.insert(track.id).inserted { return track }
            let copy = track.withNewId()
            seen.insert(copy.id)
            return copy
        }
    }
    
    private func setupDefaults() {
        let fav = Playlist(id: favoritesPlaylistId, name: "Favorites", iconName: "heart.fill", tracks: [], isBuiltIn: true)
        let local = Playlist(id: localLibraryPlaylistId, name: "Local Library", iconName: "folder.fill", tracks: [], isBuiltIn: true)
        let sampleChill = Playlist(
            name: "Lofi & Chill Beats",
            iconName: "cup.and.saucer.fill",
            tracks: [
                MediaTrack(
                    title: "Lofi Hip Hop Radio - Beats to Relax/Study to",
                    artist: "Lofi Girl",
                    duration: 3600,
                    sourceType: .youtube,
                    mediaType: .video,
                    originalURL: "https://www.youtube.com/watch?v=jfKfPfyJRdk",
                    thumbnailURL: "https://img.youtube.com/vi/jfKfPfyJRdk/hqdefault.jpg",
                    youtubeId: "jfKfPfyJRdk"
                )
            ]
        )
        
        self.playlists = [fav, local, sampleChill]
        save()
    }
    
    public func addPlaylist(name: String, iconName: String = "music.note.list") {
        let newPlaylist = Playlist(name: name, iconName: iconName, tracks: [], isBuiltIn: false)
        playlists.append(newPlaylist)
        save()
    }
    
    public func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }
    
    public func renamePlaylist(id: UUID, newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists[index].name = trimmed
        save()
    }
    
    @discardableResult
    public func mergePlaylists(sourceId: UUID, targetId: UUID, skipDuplicates: Bool = true, deleteSource: Bool = false) -> Int {
        guard let sourceIndex = playlists.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = playlists.firstIndex(where: { $0.id == targetId }),
              sourceId != targetId else { return 0 }
        
        let sourceTracks = playlists[sourceIndex].tracks
        var targetTracks = playlists[targetIndex].tracks
        
        func normalizedKey(_ track: MediaTrack) -> String {
            let t = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let a = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(t)|\(a)"
        }
        
        var existingKeys = Set(targetTracks.map { normalizedKey($0) })
        var existingURLs = Set(targetTracks.map { $0.originalURL.lowercased() })
        var addedCount = 0
        
        for track in sourceTracks {
            if skipDuplicates {
                let key = normalizedKey(track)
                let urlKey = track.originalURL.lowercased()
                let urlMatch = !urlKey.isEmpty && existingURLs.contains(urlKey)
                let keyMatch = !track.title.isEmpty && existingKeys.contains(key)
                
                if !urlMatch && !keyMatch {
                    targetTracks.append(track)
                    if !urlKey.isEmpty { existingURLs.insert(urlKey) }
                    if !track.title.isEmpty { existingKeys.insert(key) }
                    addedCount += 1
                }
            } else {
                targetTracks.append(track)
                addedCount += 1
            }
        }
        
        playlists[targetIndex].tracks = Self.uniquingTrackIds(targetTracks)
        
        if deleteSource && !playlists[sourceIndex].isBuiltIn {
            playlists.removeAll { $0.id == sourceId }
        }
        
        save()
        return addedCount
    }
    
    @discardableResult
    public func createMergedPlaylist(name: String, sourceIds: [UUID], skipDuplicates: Bool = true, deleteSources: Bool = false) -> UUID? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !sourceIds.isEmpty else { return nil }
        
        func normalizedKey(_ track: MediaTrack) -> String {
            let t = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let a = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(t)|\(a)"
        }
        
        var combinedTracks: [MediaTrack] = []
        var existingKeys = Set<String>()
        var existingURLs = Set<String>()
        
        for id in sourceIds {
            guard let pl = playlists.first(where: { $0.id == id }) else { continue }
            for track in pl.tracks {
                if skipDuplicates {
                    let key = normalizedKey(track)
                    let urlKey = track.originalURL.lowercased()
                    let urlMatch = !urlKey.isEmpty && existingURLs.contains(urlKey)
                    let keyMatch = !track.title.isEmpty && existingKeys.contains(key)
                    
                    if !urlMatch && !keyMatch {
                        combinedTracks.append(track)
                        if !urlKey.isEmpty { existingURLs.insert(urlKey) }
                        if !track.title.isEmpty { existingKeys.insert(key) }
                    }
                } else {
                    combinedTracks.append(track)
                }
            }
        }
        
        let newPlaylist = Playlist(
            name: trimmedName,
            iconName: "music.note.list",
            tracks: Self.uniquingTrackIds(combinedTracks),
            isBuiltIn: false
        )
        playlists.append(newPlaylist)
        
        if deleteSources {
            let deleteSet = Set(sourceIds)
            playlists.removeAll { deleteSet.contains($0.id) && !$0.isBuiltIn }
        }
        
        save()
        return newPlaylist.id
    }
    
    public func addTrack(_ track: MediaTrack, to playlistId: UUID, allowDuplicate: Bool = false) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if allowDuplicate || !playlists[index].tracks.contains(where: { $0.originalURL == track.originalURL }) {
            playlists[index].tracks = Self.uniquingTrackIds(playlists[index].tracks + [track])
            save()
        }
    }
    
    // MARK: - Move / Copy Between Playlists
    
    public enum TransferResult { case moved, copied, alreadyThere, notFound }
    
    /// Moves a song from one playlist to another. If the destination already has the same song,
    /// it is only removed from the source (no duplicate is created).
    @discardableResult
    public func moveTrack(_ trackId: UUID, from sourceId: UUID, to destinationId: UUID) -> TransferResult {
        guard sourceId != destinationId,
              let si = playlists.firstIndex(where: { $0.id == sourceId }),
              let di = playlists.firstIndex(where: { $0.id == destinationId }),
              let track = playlists[si].tracks.first(where: { $0.id == trackId }) else { return .notFound }
        
        playlists[si].tracks.removeAll { $0.id == trackId }
        if playlists[di].tracks.contains(where: { Self.isSameSong($0, track) }) {
            save()
            return .alreadyThere
        }
        playlists[di].tracks = Self.uniquingTrackIds(playlists[di].tracks + [track])
        save()
        return .moved
    }
    
    /// Adds a copy of a song to another playlist, leaving the original where it is.
    @discardableResult
    public func copyTrack(_ trackId: UUID, from sourceId: UUID, to destinationId: UUID) -> TransferResult {
        guard sourceId != destinationId,
              let si = playlists.firstIndex(where: { $0.id == sourceId }),
              let di = playlists.firstIndex(where: { $0.id == destinationId }),
              let track = playlists[si].tracks.first(where: { $0.id == trackId }) else { return .notFound }
        if playlists[di].tracks.contains(where: { Self.isSameSong($0, track) }) { return .alreadyThere }
        playlists[di].tracks = Self.uniquingTrackIds(playlists[di].tracks + [track])
        save()
        return .copied
    }
    
    // MARK: - Video Feedback (👍 / 👎)
    
    /// The song this track id refers to, as saved (the playing copy may carry unsaved changes)
    public func savedTrack(id: UUID) -> MediaTrack? {
        for pl in playlists { if let t = pl.tracks.first(where: { $0.id == id }) { return t } }
        return nil
    }
    
    /// 👍: always play this video for this song.
    public func confirmVideo(trackId: UUID, videoId: String) {
        updateTrackVideo(trackId: trackId, newVideoId: videoId)
    }
    
    /// 👎: never play this video for this song again.
    public func rejectVideo(trackId: UUID, videoId: String) {
        for i in playlists.indices {
            for j in playlists[i].tracks.indices where playlists[i].tracks[j].id == trackId {
                var rejected = playlists[i].tracks[j].rejectedVideoIds ?? []
                if !rejected.contains(videoId) { rejected.append(videoId) }
                playlists[i].tracks[j].rejectedVideoIds = rejected
                // Forget it if it had been saved as this song's video
                if playlists[i].tracks[j].youtubeId == videoId && !playlists[i].tracks[j].originalURL.lowercased().hasPrefix("http") {
                    playlists[i].tracks[j].youtubeId = nil
                }
            }
        }
        save()
    }
    
    // MARK: - Automatic Apple Music sync
    
    private var isSyncingAppleMusic = false
    
    /// Pulls play counts, album, genre, composer and year from Apple Music into the library.
    /// Runs on its own at launch and when the app is reopened (at most every 10 minutes), and only
    /// while Music is open, so it never launches Music unasked, except for the very first sync.
    public func autoSyncAppleMusic(force: Bool = false) async {
        guard !isSyncingAppleMusic else { return }
        let key = "lastAppleMusicSync"
        let last = UserDefaults.standard.double(forKey: key)
        if !force && Date().timeIntervalSince1970 - last < 600 { return }
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        guard force || musicRunning || last == 0 else { return }
        
        isSyncingAppleMusic = true
        defer { isSyncingAppleMusic = false }
        do {
            let details = try await AppleMusicService.shared.fetchLibraryDetails()
            let updated = applySongDetails(details)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
            AppLog.log("sync", "Apple Music sync: \(details.count) library songs, \(updated) updated here")
        } catch {
            AppLog.log("sync", "Apple Music sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Start / End Time
    
    /// Sets where a song starts and stops, on every copy of it (same id or same link).
    public func setTrimTimes(for track: MediaTrack, start: Double?, end: Double?) {
        let s = (start ?? 0) > 0 ? start : nil
        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                let t = playlists[i].tracks[j]
                if t.id == track.id || (!t.originalURL.isEmpty && t.originalURL == track.originalURL) {
                    playlists[i].tracks[j].startTime = s
                    playlists[i].tracks[j].endTime = end
                }
            }
        }
        save()
    }
    
    // MARK: - Song Details
    
    /// Fills album / composer / year (and missing durations) from Apple Music, matching on title + artist.
    /// Returns how many songs were updated.
    @discardableResult
    public func applySongDetails(_ details: [AppleMusicTrackDetails]) -> Int {
        func key(_ title: String, _ artist: String) -> String {
            "\(title.lowercased().trimmingCharacters(in: .whitespaces))|\(artist.lowercased().trimmingCharacters(in: .whitespaces))"
        }
        var byKey: [String: AppleMusicTrackDetails] = [:]
        var byTitle: [String: [AppleMusicTrackDetails]] = [:]
        for d in details {
            byKey[key(d.name, d.artist)] = d
            byTitle[d.name.lowercased(), default: []].append(d)
        }
        
        var updated = 0
        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                let t = playlists[i].tracks[j]
                // Exact title+artist, or the title alone when it's unambiguous
                let candidates = byTitle[t.title.lowercased()] ?? []
                guard let d = byKey[key(t.title, t.artist)] ?? (candidates.count == 1 ? candidates.first : nil) else { continue }
                var changed = false
                if !d.album.isEmpty && t.album != d.album { playlists[i].tracks[j].album = d.album; changed = true }
                if !d.composer.isEmpty && t.composer != d.composer { playlists[i].tracks[j].composer = d.composer; changed = true }
                if d.year > 0 && t.year != d.year { playlists[i].tracks[j].year = d.year; changed = true }
                if !d.genre.isEmpty && t.genre != d.genre { playlists[i].tracks[j].genre = d.genre; changed = true }
                // The real "added" date from Apple Music (imports otherwise all carry the import day)
                if let added = d.dateAdded, abs(added.timeIntervalSince(t.dateAdded)) > 60 {
                    playlists[i].tracks[j].dateAdded = added; changed = true
                }
                if d.plays != (t.applePlayCount ?? 0) { playlists[i].tracks[j].applePlayCount = d.plays > 0 ? d.plays : nil; changed = true }
                if t.duration <= 0 && d.duration > 0 { playlists[i].tracks[j].duration = d.duration; changed = true }
                if changed { updated += 1 }
            }
        }
        if updated > 0 { save() }
        return updated
    }
    
    // MARK: - Duplicate Detection
    
    /// True when two tracks are the same song: same YouTube video, same link, or same title and artist.
    public static func isSameSong(_ a: MediaTrack, _ b: MediaTrack) -> Bool {
        if let idA = a.youtubeId, !idA.isEmpty, idA == b.youtubeId { return true }
        if !a.originalURL.isEmpty && a.originalURL.lowercased() == b.originalURL.lowercased() { return true }
        func key(_ t: MediaTrack) -> String {
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = t.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(title)|\(artist)"
        }
        return !a.title.isEmpty && key(a) == key(b)
    }
    
    /// A saved song that a newly found YouTube video is probably a video of, even though the titles differ:
    /// saved "Sandalee" (Velmurugan & Mahalingam) vs video "Sema Songs | Sandalee Video Song | G.V. Prakash Kumar".
    public static func isVideoOfSavedSong(saved: MediaTrack, found: MediaTrack) -> Bool {
        if isSameSong(saved, found) { return true }
        let song = ArtistPhotoService.normalize(saved.coreTitle)
        guard song.count >= 5 else { return false }   // short titles ("365", "Zoo") match too much
        
        let title = ArtistPhotoService.normalize(found.title)
        guard title.contains(song) else { return false }
        
        // The song name alone isn't enough: the movie, or one of the singers, must also show up
        let context = ArtistPhotoService.normalize(found.title + found.artist)
        if let movie = saved.movieName, ArtistPhotoService.normalize(movie).count >= 3,
           context.contains(ArtistPhotoService.normalize(movie)) { return true }
        let savedArtists = splitArtists(saved.artist).map { ArtistPhotoService.normalize($0) }.filter { $0.count >= 4 }
        if savedArtists.contains(where: { context.contains($0) }) { return true }
        // The video title is essentially just the song (maybe "Video Song" / "Official Video")
        let rest = title.replacingOccurrences(of: song, with: "")
            .replacingOccurrences(of: "videosong", with: "").replacingOccurrences(of: "officialvideo", with: "")
            .replacingOccurrences(of: "fullvideo", with: "").replacingOccurrences(of: "official", with: "")
        return rest.count <= 6
    }
    
    /// Saved songs, with the playlists holding them, that this video is probably a video of.
    public func savedSongs(matching found: MediaTrack) -> [(playlist: Playlist, track: MediaTrack)] {
        var result: [(Playlist, MediaTrack)] = []
        for pl in playlists {
            for t in pl.tracks where Self.isVideoOfSavedSong(saved: t, found: found) {
                result.append((pl, t))
            }
        }
        return result
    }
    
    /// Points every saved copy of this song at a different YouTube video.
    public func setVideo(forSongsLike saved: MediaTrack, videoId: String, thumbnailURL: String? = nil) {
        for pl in playlists {
            for t in pl.tracks where Self.isSameSong(t, saved) {
                updateTrackVideo(trackId: t.id, newVideoId: videoId, newThumbnailURL: thumbnailURL)
            }
        }
    }
    
    /// Playlists that already contain the given song.
    public func playlistsContaining(_ track: MediaTrack) -> [Playlist] {
        playlists.filter { pl in pl.tracks.contains { Self.isVideoOfSavedSong(saved: $0, found: track) } }
    }
    
    /// Adds many tracks with a single save, skipping ones already in the playlist.
    public func addTracks(_ tracks: [MediaTrack], to playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        var existingURLs = Set(playlists[index].tracks.map(\.originalURL))
        var newTracks: [MediaTrack] = []
        for track in tracks where existingURLs.insert(track.originalURL).inserted {
            newTracks.append(track)
        }
        guard !newTracks.isEmpty else { return }
        playlists[index].tracks = Self.uniquingTrackIds(playlists[index].tracks + newTracks)
        save()
    }
    
    public func removeTrack(trackId: UUID, from playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].tracks.removeAll { $0.id == trackId }
        save()
    }
    
    public func updateTrackVideo(trackId: UUID, newVideoId: String, newThumbnailURL: String? = nil) {
        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                if playlists[i].tracks[j].id == trackId {
                    playlists[i].tracks[j].youtubeId = newVideoId
                    playlists[i].tracks[j].sourceType = .youtube
                    playlists[i].tracks[j].mediaType = .video
                    if let thumb = newThumbnailURL {
                        playlists[i].tracks[j].thumbnailURL = thumb
                    } else if playlists[i].tracks[j].thumbnailURL == nil || playlists[i].tracks[j].thumbnailURL?.contains("img.youtube.com") == true {
                        playlists[i].tracks[j].thumbnailURL = "https://img.youtube.com/vi/\(newVideoId)/hqdefault.jpg"
                    }
                }
            }
        }
        save()
    }
    
    public func toggleFavorite(track: MediaTrack) {
        guard let favIndex = playlists.firstIndex(where: { $0.id == favoritesPlaylistId }) else { return }
        
        if let existingIdx = playlists[favIndex].tracks.firstIndex(where: { $0.originalURL == track.originalURL }) {
            playlists[favIndex].tracks.remove(at: existingIdx)
        } else {
            var favTrack = track
            favTrack.isFavorite = true
            playlists[favIndex].tracks.append(favTrack)
        }
        
        // Update favorite flag across all playlists
        let isFav = playlists[favIndex].tracks.contains(where: { $0.originalURL == track.originalURL })
        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                if playlists[i].tracks[j].originalURL == track.originalURL {
                    playlists[i].tracks[j].isFavorite = isFav
                }
            }
        }
        
        save()
    }
    
    public func isFavorite(track: MediaTrack) -> Bool {
        guard let fav = favoritesPlaylist else { return false }
        return fav.tracks.contains(where: { $0.originalURL == track.originalURL })
    }
    
    // MARK: - Play Count Tracking
    public func recordPlay(for track: MediaTrack) {
        var didUpdate = false
        for i in playlists.indices {
            for j in playlists[i].tracks.indices {
                if playlists[i].tracks[j].originalURL == track.originalURL || playlists[i].tracks[j].id == track.id {
                    playlists[i].tracks[j].playCount += 1
                    playlists[i].tracks[j].lastPlayedDate = Date()
                    didUpdate = true
                }
            }
        }
        if didUpdate {
            save()
        }
    }
    
    // MARK: - Unique Tracks & Artists Grouping
    public var allUniqueTracks: [MediaTrack] {
        var seen = Set<String>()
        var result: [MediaTrack] = []
        for pl in playlists {
            for track in pl.tracks {
                let key = "\(track.title.lowercased())-\(track.artist.lowercased())"
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(track)
                }
            }
        }
        return result
    }
    
    /// Every singer as their own entry: a song by "Sid Sriram & Anirudh" appears under both.
    public var allArtists: [ArtistGroup] {
        var tracksByArtist: [String: [MediaTrack]] = [:]
        var spellings: [String: [String: Int]] = [:]   // key → how often each spelling appears
        
        for track in allUniqueTracks {
            for name in Self.splitArtists(track.artist) {
                let key = ArtistPhotoService.normalize(name)
                guard !key.isEmpty else { continue }
                tracksByArtist[key, default: []].append(track)
                spellings[key, default: [:]][name, default: 0] += 1
            }
        }
        
        return tracksByArtist.map { key, tracks in
            // "S.P. Balasubrahmanyam" / "S. P. Balasubrahmanyam": show the spelling used most
            let name = spellings[key]?.max { $0.value < $1.value }?.key ?? key
            let playCount = tracks.reduce(0) { $0 + $1.totalPlays }
            return ArtistGroup(
                name: name,
                trackCount: tracks.count,
                totalPlayCount: playCount,
                tracks: tracks,
                sampleArtworkURL: tracks.compactMap { $0.thumbnailURL }.first
            )
        }
        .sorted { ($0.trackCount, $0.name) > ($1.trackCount, $1.name) }
    }
    
    /// Names that contain a separator but are one act
    private static let wholeNames = ["Simon & Garfunkel", "Earth, Wind & Fire", "Hall & Oates", "Florence + The Machine",
                                     "Mumford & Sons", "Years & Years", "Of Monsters and Men", "Tom & Jerry",
                                     "Shankar-Ehsaan-Loy", "Vishal-Shekhar", "Vishal & Shekhar", "Salim-Sulaiman", "Salim–Sulaiman",
                                     "Sachin-Jigar", "Jatin-Lalit", "Laxmikant-Pyarelal", "Nadeem-Shravan"]
    
    /// "Zedd & Katy Perry" → ["Zedd", "Katy Perry"]; "Hari (Live), Chitra feat. X" → ["Hari", "Chitra", "X"]
    public static func splitArtists(_ raw: String) -> [String] {
        var text = raw.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        
        // Shield acts whose names contain "&" or "," so they stay in one piece
        var shielded: [String: String] = [:]
        for (i, whole) in wholeNames.enumerated() where text.range(of: whole, options: .caseInsensitive) != nil {
            let token = "§\(i)§"
            shielded[token] = whole
            text = text.replacingOccurrences(of: whole, with: token, options: .caseInsensitive)
        }
        
        let parts = text.replacingOccurrences(of: #"(?i)\s+(feat\.?|ft\.?|featuring|with|vs\.?|x)\s+"#, with: ",", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "&,;/+"))
        
        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            for (token, whole) in shielded { name = name.replacingOccurrences(of: token, with: whole) }
            let key = ArtistPhotoService.normalize(name)
            guard !key.isEmpty, name.lowercased() != "various artists", name != "Unknown Artist", seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }
    
    /// Every song once, newest addition first
    public var recentlyAddedTracks: [MediaTrack] {
        allUniqueTracks.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    public var mostPlayedTracks: [MediaTrack] {
        allUniqueTracks
            .filter { $0.totalPlays > 0 }
            .sorted { $0.totalPlays > $1.totalPlays }
    }
}
