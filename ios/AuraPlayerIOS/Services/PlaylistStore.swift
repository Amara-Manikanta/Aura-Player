import Foundation
import SwiftUI
import Combine

@MainActor
public class PlaylistStore: ObservableObject {
    public static let shared = PlaylistStore()
    
    @Published public var playlists: [Playlist] = []
    public var artistPhotos: [String: String] = [:]
    public var trackArtworkCache: [String: String] = [:]
    
    private let saveURL: URL
    public static let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent("playlists_v2.json")
        
        loadCaches()
        load()
    }
    
    // MARK: - Playlists Accessors
    
    public var favoritesPlaylist: Playlist? {
        playlists.first { $0.id == Self.favoritesId || $0.name.lowercased() == "favorites" }
    }
    
    public var mostPlayedTracks: [MediaTrack] {
        var allTracks: [MediaTrack] = []
        for pl in playlists {
            allTracks.append(contentsOf: pl.tracks)
        }
        var uniqueDict: [UUID: MediaTrack] = [:]
        for t in allTracks {
            if let existing = uniqueDict[t.id] {
                if t.playCount > existing.playCount {
                    uniqueDict[t.id] = t
                }
            } else {
                uniqueDict[t.id] = t
            }
        }
        return uniqueDict.values
            .sorted { ($0.playCount, $0.applePlayCount ?? 0) > ($1.playCount, $1.applePlayCount ?? 0) }
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
    
    public var recentlyAddedTracks: [MediaTrack] {
        allUniqueTracks.sorted { $0.dateAdded > $1.dateAdded }
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
    
    public func createBackupFileURL() -> URL? {
        do {
            let backupURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("AuraPlayer_Library_Backup.json")
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: backupURL, options: .atomic)
            return backupURL
        } catch {
            print("Failed to create backup file: \(error)")
            return nil
        }
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
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: saveURL, options: .atomic)
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
