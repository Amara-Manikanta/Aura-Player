import Foundation
import MediaPlayer

/// Brings the iPhone's Apple Music library into the app, like the Mac app's automatic sync:
/// play counts, the real "added" date (for Recently Added), album, genre, composer and year,
/// plus songs added to Apple Music since the last import.
@MainActor
public final class AppleMusicSync: ObservableObject {
    public static let shared = AppleMusicSync()

    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastResult: String?

    private static let lastSyncKey = "lastAppleMusicSync"

    public var lastSync: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    public var isAuthorized: Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    /// At launch / when the app comes back: at most every 10 minutes, and only once allowed
    /// (the permission prompt is shown only from the Sync button).
    public func autoSync() async {
        guard isAuthorized else { return }
        if let last = lastSync, Date().timeIntervalSince(last) < 600 { return }
        await sync(store: PlaylistStore.shared)
    }

    /// Asks for access if needed, then syncs.
    @discardableResult
    public func syncNow() async -> String {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
                MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
            }
        }
        guard isAuthorized else {
            let msg = "Allow Aura Player to access Apple Music in Settings › Privacy › Media & Apple Music."
            lastResult = msg
            return msg
        }
        return await sync(store: PlaylistStore.shared)
    }

    struct LibrarySong: Sendable {
        let title: String
        let artist: String
        let album: String
        let composer: String
        let genre: String
        let year: Int
        let duration: Double
        let plays: Int
        let dateAdded: Date
    }

    @discardableResult
    private func sync(store: PlaylistStore) async -> String {
        guard !isSyncing else { return lastResult ?? "" }
        isSyncing = true
        defer { isSyncing = false }

        // Reading thousands of songs takes a moment: off the main thread
        let songs: [LibrarySong] = await Task.detached(priority: .utility) {
            (MPMediaQuery.songs().items ?? []).compactMap { item -> LibrarySong? in
                guard item.mediaType.contains(.music), let title = item.title, !title.isEmpty else { return nil }
                let year = item.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                return LibrarySong(title: title, artist: item.artist ?? "Unknown Artist",
                                   album: item.albumTitle ?? "", composer: item.composer ?? "",
                                   genre: item.genre ?? "", year: year, duration: item.playbackDuration,
                                   plays: item.playCount, dateAdded: item.dateAdded)
            }
        }.value
        guard !songs.isEmpty else {
            let msg = "No songs found in this iPhone's Apple Music library."
            lastResult = msg
            return msg
        }

        let updated = apply(songs, to: store)
        let added = importNewSongs(songs, into: store)
        if updated > 0 || added > 0 { store.save() }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
        let msg = "Synced \(songs.count) Apple Music songs: \(updated) updated" + (added > 0 ? ", \(added) new songs added to Music." : ".")
        print("[sync] \(msg)")
        lastResult = msg
        return msg
    }

    private static func key(_ title: String, _ artist: String) -> String {
        "\(title.lowercased().trimmingCharacters(in: .whitespaces))|\(artist.lowercased().trimmingCharacters(in: .whitespaces))"
    }

    /// Same matching as the Mac: exact title + artist, or the title alone when it's unambiguous.
    private func apply(_ songs: [LibrarySong], to store: PlaylistStore) -> Int {
        var byKey: [String: LibrarySong] = [:]
        var byTitle: [String: [LibrarySong]] = [:]
        for s in songs {
            byKey[Self.key(s.title, s.artist)] = s
            byTitle[s.title.lowercased(), default: []].append(s)
        }
        var updated = 0
        var lists = store.playlists   // one change for SwiftUI, not thousands
        defer { if updated > 0 { store.playlists = lists } }
        for i in lists.indices {
            for j in lists[i].tracks.indices {
                let t = lists[i].tracks[j]
                let candidates = byTitle[t.title.lowercased()] ?? []
                guard let d = byKey[Self.key(t.title, t.artist)] ?? (candidates.count == 1 ? candidates.first : nil) else { continue }
                var track = t
                if !d.album.isEmpty { track.album = d.album }
                if !d.composer.isEmpty { track.composer = d.composer }
                if d.year > 0 { track.year = d.year }
                if !d.genre.isEmpty { track.genre = d.genre }
                // The real "added" date from Apple Music (imports otherwise all carry the import day)
                if abs(d.dateAdded.timeIntervalSince(t.dateAdded)) > 60 { track.dateAdded = d.dateAdded }
                // Apple Music's own count; the app's plays are kept separately and added on top
                track.applePlayCount = d.plays > 0 ? d.plays : nil
                if t.duration <= 0 && d.duration > 0 { track.duration = d.duration }
                if track != t {
                    lists[i].tracks[j] = track
                    updated += 1
                }
            }
        }
        return updated
    }

    /// Songs added to Apple Music after the newest song already imported go into "Music"
    /// (the playlist the Mac's full Apple Music import created).
    private func importNewSongs(_ songs: [LibrarySong], into store: PlaylistStore) -> Int {
        guard let musicIndex = store.playlists.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "music" }),
              let newest = store.playlists[musicIndex].tracks.map(\.dateAdded).max() else { return 0 }
        let known = Set(store.allUniqueTracks.map { Self.key($0.title, $0.artist) })
        let fresh = songs
            .filter { $0.dateAdded > newest.addingTimeInterval(60) && !known.contains(Self.key($0.title, $0.artist)) }
            .sorted { $0.dateAdded < $1.dateAdded }
        for s in fresh {
            var track = MediaTrack(
                title: s.title, artist: s.artist, duration: s.duration,
                sourceType: .youtube, mediaType: .video,
                originalURL: "\(s.title) \(s.artist)",   // same shape as the Mac's Apple Music import
                dateAdded: s.dateAdded,
                album: s.album.isEmpty ? nil : s.album,
                composer: s.composer.isEmpty ? nil : s.composer,
                year: s.year > 0 ? s.year : nil
            )
            track.genre = s.genre.isEmpty ? nil : s.genre
            track.applePlayCount = s.plays > 0 ? s.plays : nil
            store.playlists[musicIndex].tracks.append(track)   // a handful at most
        }
        return fresh.count
    }
}
