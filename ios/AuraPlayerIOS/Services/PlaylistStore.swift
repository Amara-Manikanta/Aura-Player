import Foundation
import SwiftUI
import Combine

@MainActor
public class PlaylistStore: ObservableObject {
    public static let shared = PlaylistStore()
    
    @Published public var playlists: [Playlist] = [] {
        didSet { derived = DerivedLists() }   // anything computed from the library is stale now
    }
    
    /// Lists computed from the whole library (3,000+ songs). Rebuilt only after the library changes,
    /// not on every screen redraw.
    final class DerivedLists {
        var unique: [MediaTrack]?
        var mostPlayed: [MediaTrack]?
        var recent: [MediaTrack]?
        var artists: [ArtistGroup]?
    }
    var derived = DerivedLists()
    public var artistPhotos: [String: String] = [:]
    public var trackArtworkCache: [String: String] = [:]
    
    private let saveURL: URL
    public static let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent("playlists_v2.json")
        
        loadCaches()
        load()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }
    
    // MARK: - Playlists Accessors
    
    public var favoritesPlaylist: Playlist? {
        playlists.first { $0.id == Self.favoritesId || $0.name.lowercased() == "favorites" }
    }
    
    /// Apple Music plays + plays in this app, most first (same as the Mac app)
    public var mostPlayedTracks: [MediaTrack] {
        if let cached = derived.mostPlayed { return cached }
        let sorted = allUniqueTracks
            .filter { $0.totalPlays > 0 }
            .sorted { $0.totalPlays > $1.totalPlays }
        derived.mostPlayed = sorted
        return sorted
    }
    
    public var artistsMap: [String: [MediaTrack]] {
        var map: [String: [MediaTrack]] = [:]
        for pl in playlists {
            for track in pl.tracks {
                let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                if !artist.isEmpty && artist != "Unknown Artist" {
                    map[artist, default: []].append(track)
                }
            }
        }
        // Deduplicate tracks per artist
        for (artist, tracks) in map {
            var seen = Set<String>()
            var unique: [MediaTrack] = []
            for t in tracks {
                let key = "\(t.title.lowercased())|\(t.duration)"
                if seen.insert(key).inserted {
                    unique.append(t)
                }
            }
            map[artist] = unique
        }
        return map
    }
    
    public var allUniqueTracks: [MediaTrack] {
        if let cached = derived.unique { return cached }
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
        derived.unique = result
        return result
    }
    
    public var recentlyAddedTracks: [MediaTrack] {
        if let cached = derived.recent { return cached }
        let sorted = allUniqueTracks.sorted { $0.dateAdded > $1.dateAdded }
        derived.recent = sorted
        return sorted
    }
    
    // MARK: - Operations
    
    public func createPlaylist(name: String) -> Playlist {
        let newPl = Playlist(
            name: name,
            iconName: "music.note.list",
            tracks: [],
            isBuiltIn: false
        )
        playlists.append(newPl)
        save()
        return newPl
    }
    
    public func renamePlaylist(id: UUID, newName: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            playlists[idx].name = clean
            save()
        }
    }
    
    public func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }
    
    public func addTrack(_ track: MediaTrack, to playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !playlists[idx].tracks.contains(where: { $0.id == track.id || ($0.youtubeId != nil && $0.youtubeId == track.youtubeId) }) {
            playlists[idx].tracks.append(track)
            save()
        }
    }
    
    public func removeTrack(trackId: UUID, from playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].tracks.removeAll { $0.id == trackId }
        save()
    }
    
    public func toggleFavorite(track: MediaTrack) {
        guard let favIdx = playlists.firstIndex(where: { $0.id == Self.favoritesId || $0.name.lowercased() == "favorites" }) else { return }
        let isFav = playlists[favIdx].tracks.contains { $0.id == track.id || ($0.youtubeId != nil && $0.youtubeId == track.youtubeId) }
        
        if isFav {
            playlists[favIdx].tracks.removeAll { $0.id == track.id || ($0.youtubeId != nil && $0.youtubeId == track.youtubeId) }
        } else {
            var updated = track
            updated.isFavorite = true
            playlists[favIdx].tracks.insert(updated, at: 0)
        }
        
        // Update favorite flag across all playlists
        for pIdx in playlists.indices {
            for tIdx in playlists[pIdx].tracks.indices {
                if playlists[pIdx].tracks[tIdx].id == track.id || (playlists[pIdx].tracks[tIdx].youtubeId != nil && playlists[pIdx].tracks[tIdx].youtubeId == track.youtubeId) {
                    playlists[pIdx].tracks[tIdx].isFavorite = !isFav
                }
            }
        }
        
        save()
    }
    
    // MARK: - Song edits (saved immediately)
    
    /// The saved copy of a song (the playing copy may carry unsaved changes)
    public func savedTrack(id: UUID) -> MediaTrack? {
        for pl in playlists { if let t = pl.tracks.first(where: { $0.id == id }) { return t } }
        return nil
    }
    
    private func updateTracks(where match: (MediaTrack) -> Bool, _ change: (inout MediaTrack) -> Void) {
        for p in playlists.indices {
            for t in playlists[p].tracks.indices where match(playlists[p].tracks[t]) {
                change(&playlists[p].tracks[t])
            }
        }
        save()
    }
    
    /// Where a song starts and stops, on every copy of it (same id or same link)
    public func setTrimTimes(for track: MediaTrack, start: Double?, end: Double?) {
        let s = (start ?? 0) > 0 ? start : nil
        updateTracks(where: { $0.id == track.id || (!$0.originalURL.isEmpty && $0.originalURL == track.originalURL) }) {
            $0.startTime = s
            $0.endTime = end
        }
    }
    
    /// Renames a song on every copy of it (same id or same link)
    public func renameSong(_ track: MediaTrack, title: String, artist: String) {
        updateTracks(where: { $0.id == track.id || (!$0.originalURL.isEmpty && $0.originalURL == track.originalURL) }) {
            $0.title = title
            $0.artist = artist
        }
    }
    
    /// Points a song at a YouTube video (Change Video Link, or 👍 on the playing video)
    public func setVideo(trackId: UUID, videoId: String, thumbnailURL: String? = nil) {
        updateTracks(where: { $0.id == trackId }) {
            $0.youtubeId = videoId
            if let thumbnailURL { $0.thumbnailURL = thumbnailURL }
        }
    }
    
    /// 👎: never play this video for this song again
    public func rejectVideo(trackId: UUID, videoId: String) {
        updateTracks(where: { $0.id == trackId }) {
            var rejected = $0.rejectedVideoIds ?? []
            if !rejected.contains(videoId) { rejected.append(videoId) }
            $0.rejectedVideoIds = rejected
            if $0.youtubeId == videoId && !$0.originalURL.lowercased().hasPrefix("http") { $0.youtubeId = nil }
        }
    }
    
    // MARK: - Move / copy between playlists
    
    public enum TransferResult { case moved, copied, alreadyThere, notFound }
    
    /// Same song: same YouTube video, same link, or same title and artist
    public static func isSameSong(_ a: MediaTrack, _ b: MediaTrack) -> Bool {
        if let idA = a.youtubeId, !idA.isEmpty, idA == b.youtubeId { return true }
        if !a.originalURL.isEmpty && a.originalURL.lowercased() == b.originalURL.lowercased() { return true }
        let key = { (t: MediaTrack) in "\(t.title.lowercased().trimmingCharacters(in: .whitespaces))|\(t.artist.lowercased().trimmingCharacters(in: .whitespaces))" }
        return !a.title.isEmpty && key(a) == key(b)
    }
    
    @discardableResult
    public func moveTrack(_ trackId: UUID, from sourceId: UUID, to destinationId: UUID) -> TransferResult {
        guard sourceId != destinationId,
              let si = playlists.firstIndex(where: { $0.id == sourceId }),
              let di = playlists.firstIndex(where: { $0.id == destinationId }),
              let track = playlists[si].tracks.first(where: { $0.id == trackId }) else { return .notFound }
        playlists[si].tracks.removeAll { $0.id == trackId }
        let exists = playlists[di].tracks.contains { Self.isSameSong($0, track) }
        if !exists { playlists[di].tracks.append(track) }
        save()
        return exists ? .alreadyThere : .moved
    }
    
    @discardableResult
    public func copyTrack(_ track: MediaTrack, to destinationId: UUID) -> TransferResult {
        guard let di = playlists.firstIndex(where: { $0.id == destinationId }) else { return .notFound }
        if playlists[di].tracks.contains(where: { Self.isSameSong($0, track) }) { return .alreadyThere }
        var copy = track
        if playlists[di].tracks.contains(where: { $0.id == track.id }) { copy = track.withNewId() }
        playlists[di].tracks.append(copy)
        save()
        return .copied
    }
    
    public func isTrackFavorite(_ track: MediaTrack) -> Bool {
        guard let fav = favoritesPlaylist else { return false }
        return fav.tracks.contains { $0.id == track.id || ($0.youtubeId != nil && $0.youtubeId == track.youtubeId) }
    }
    
    public func recordPlay(track: MediaTrack) {
        for pIdx in playlists.indices {
            for tIdx in playlists[pIdx].tracks.indices {
                if playlists[pIdx].tracks[tIdx].id == track.id || (playlists[pIdx].tracks[tIdx].youtubeId != nil && playlists[pIdx].tracks[tIdx].youtubeId == track.youtubeId) {
                    playlists[pIdx].tracks[tIdx].playCount += 1
                    playlists[pIdx].tracks[tIdx].lastPlayedDate = Date()
                }
            }
        }
        save()
    }
    
    // MARK: - Storage & Bundled macOS Data Loading
    
    private func loadCaches() {
        // Load artist photos cache
        if let photoURL = Bundle.main.url(forResource: "artist_photos", withExtension: "json", subdirectory: "Resources") ??
                          Bundle.main.url(forResource: "artist_photos", withExtension: "json") {
            if let data = try? Data(contentsOf: photoURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                self.artistPhotos = decoded
            }
        }
        
        // Load track artwork cache
        if let artURL = Bundle.main.url(forResource: "track_artwork", withExtension: "json", subdirectory: "Resources") ??
                        Bundle.main.url(forResource: "track_artwork", withExtension: "json") {
            if let data = try? Data(contentsOf: artURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                self.trackArtworkCache = decoded
            }
        }
    }
    
    private func load() {
        // 1. First inspect the bundled macOS library from Bundle Resources
        var bundledPlaylists: [Playlist] = []
        if let bundleURL = Bundle.main.url(forResource: "playlists", withExtension: "json", subdirectory: "Resources") ??
                           Bundle.main.url(forResource: "playlists", withExtension: "json") {
            if let data = try? Data(contentsOf: bundleURL),
               let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
                bundledPlaylists = decoded
            }
        }
        
        // 2. Try saved user file in Documents
        if FileManager.default.fileExists(atPath: saveURL.path),
           let data = try? Data(contentsOf: saveURL),
           let saved = try? JSONDecoder().decode([Playlist].self, from: data) {
            let savedTracks = saved.reduce(0) { $0 + $1.tracks.count }
            let bundleTracks = bundledPlaylists.reduce(0) { $0 + $1.tracks.count }
            
            // If user's saved library has as many or more tracks than the bundled library, use saved
            if savedTracks >= bundleTracks && savedTracks > 10 {
                self.playlists = saved
                return
            }
        }
        
        // 3. Bundled macOS library with 17 playlists and 3,432 tracks
        if !bundledPlaylists.isEmpty {
            self.playlists = bundledPlaylists
            save()
            return
        }
        
        // 4. Fallback to default playlists
        seedDefaultPlaylists()
    }
    
    /// Writes a backup file for sharing, in the background (Settings used to rebuild it on every redraw)
    public func createBackupFile() async -> URL? {
        let snapshot = playlists
        return await Task.detached(priority: .utility) { () -> URL? in
            do {
                let backupURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("AuraPlayer_Library_Backup.json")
                try JSONEncoder().encode(snapshot).write(to: backupURL, options: .atomic)
                return backupURL
            } catch {
                print("Failed to create backup file: \(error)")
                return nil
            }
        }.value
    }
    
    public func importBackup(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() || true else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([Playlist].self, from: data)
            if !imported.isEmpty {
                self.playlists = imported
                save()
                return true
            }
        } catch {
            print("Failed to import backup: \(error)")
        }
        return false
    }
    
    public func resetToBundled() {
        if let bundleURL = Bundle.main.url(forResource: "playlists", withExtension: "json", subdirectory: "Resources") ??
                           Bundle.main.url(forResource: "playlists", withExtension: "json") {
            if let data = try? Data(contentsOf: bundleURL),
               let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
                self.playlists = decoded
                save()
            }
        }
    }
    
    private var saveTask: Task<Void, Never>?
    
    /// Saves the library in the background, shortly after the last change. (Encoding 3,000+ songs on the
    /// main thread froze the app for a moment at the 10-second play count and on every edit.)
    func save() {
        saveTask?.cancel()
        let snapshot = playlists
        let url = saveURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url)
        }
    }
    
    /// A copy of the library before a sync changes it (the 3 newest are kept)
    func backUpLibrary() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: saveURL.path) else { saveNow(); return }
        saveNow()
        let dir = saveURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? fm.copyItem(at: saveURL, to: dir.appendingPathComponent("playlists_v2.backup-\(stamp).json"))
        let backups = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("playlists_v2.backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(3) { try? fm.removeItem(at: old) }
    }
    
    /// The library after a sync with the Mac
    func adoptSynced(_ synced: [Playlist]) {
        playlists = synced
        save()
    }
    
    /// Writes any pending change right now (the app is going to the background)
    func saveNow() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        Self.write(playlists, to: saveURL)
    }
    
    nonisolated private static func write(_ playlists: [Playlist], to url: URL) {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save playlists: \(error)")
        }
    }
    
    private func seedDefaultPlaylists() {
        let favorites = Playlist(
            id: Self.favoritesId,
            name: "Favorites",
            iconName: "heart.fill",
            tracks: [],
            isBuiltIn: true
        )
        self.playlists = [favorites]
        save()
    }
}
