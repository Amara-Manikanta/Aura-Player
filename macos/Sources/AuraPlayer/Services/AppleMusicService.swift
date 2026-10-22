import Foundation

public struct AppleMusicPlaylistInfo: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let trackCount: Int
}

public struct AppleMusicTrackInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(name)-\(artist)" }
    public let name: String
    public let artist: String
    public let duration: Double
    public let location: String
}

public struct AppleMusicTrackDetails: Sendable {
    public let name: String
    public let artist: String
    public let album: String
    public let composer: String
    public let year: Int
    public let duration: Double
    public let genre: String
    public let plays: Int
    /// When the song was added to the Apple Music library
    public let dateAdded: Date?
}

public actor AppleMusicService {
    public static let shared = AppleMusicService()
    
    private init() {}
    
    public func fetchUserPlaylists() async throws -> [AppleMusicPlaylistInfo] {
        let script = """
        const music = Application("Music");
        const playlists = music.userPlaylists();
        const result = [];
        for (let i = 0; i < playlists.length; i++) {
            const pl = playlists[i];
            const name = pl.name();
            // Skip non-music system categories
            if (name === "TV & Movies") continue;
            result.push({
                name: name,
                trackCount: pl.tracks.length
            });
        }
        JSON.stringify(result);
        """
        
        let output = try await runJXA(script: script)
        guard let data = output.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return jsonArray.compactMap { item in
            guard let name = item["name"] as? String,
                  let count = item["trackCount"] as? Int else { return nil }
            return AppleMusicPlaylistInfo(name: name, trackCount: count)
        }
    }
    
    /// Fetches every track in the playlist (or the first `maxCount` if given).
    public func fetchTracks(forPlaylist playlistName: String, maxCount: Int? = nil) async throws -> [MediaTrack] {
        // Escape quotes in playlistName
        let safeName = playlistName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let limitExpr = maxCount.map { "Math.min(names.length, \($0))" } ?? "names.length"
        
        // Read each property for all tracks in one Apple Event instead of one event per track,
        // which keeps playlists with thousands of songs fast.
        let script = """
        const music = Application("Music");
        const matches = music.userPlaylists.whose({name: "\(safeName)"});
        if (matches.length === 0) {
            JSON.stringify([]);
        } else {
            const pl = matches[0];
            const tracks = pl.tracks;
            const ids = tracks.persistentID();
            const names = tracks.name();
            const artists = tracks.artist();
            const durations = tracks.duration();
            const albums = tracks.album();
            const composers = tracks.composer();
            const years = tracks.year();
            const genres = tracks.genre();
            const playedCounts = tracks.playedCount();
            // Only file tracks have a location; asking all tracks fails when any are cloud-only.
            const locById = {};
            try {
                const fileIds = pl.fileTracks.persistentID();
                const fileLocs = pl.fileTracks.location();
                for (let j = 0; j < fileIds.length; j++) {
                    if (fileLocs[j]) locById[fileIds[j]] = fileLocs[j].toString();
                }
            } catch(e) {}
            const limit = \(limitExpr);
            const list = [];
            for (let i = 0; i < limit; i++) {
                const loc = locById[ids[i]] || "";
                list.push({
                    name: names[i] || "Unknown Title",
                    artist: artists[i] || "Unknown Artist",
                    duration: durations[i] || 0,
                    location: loc,
                    album: albums[i] || "",
                    composer: composers[i] || "",
                    year: years[i] || 0,
                    genre: genres[i] || "",
                    plays: playedCounts[i] || 0
                });
            }
            JSON.stringify(list);
        }
        """
        
        let output = try await runJXA(script: script)
        guard let data = output.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return jsonArray.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let artist = (item["artist"] as? String) ?? "Unknown Artist"
            let duration = (item["duration"] as? Double) ?? 0.0
            let location = (item["location"] as? String) ?? ""
            let album = (item["album"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let composer = (item["composer"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let year = (item["year"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let genre = (item["genre"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let plays = (item["plays"] as? Int) ?? 0
            
            let isLocalFile = !location.isEmpty && FileManager.default.fileExists(atPath: location)
            
            if isLocalFile {
                let ext = (location as NSString).pathExtension.lowercased()
                let isVideo = ["mp4", "mov", "mkv", "m4v"].contains(ext)
                return MediaTrack(
                    title: name,
                    artist: artist,
                    duration: duration,
                    sourceType: .local,
                    mediaType: isVideo ? .video : .audio,
                    originalURL: location,
                    album: album, composer: composer, year: year
                ).withGenre(genre).withApplePlays(plays)
            } else {
                // Query string for YouTube streaming
                let searchQuery = "\(name) \(artist)"
                return MediaTrack(
                    title: name,
                    artist: artist,
                    duration: duration,
                    sourceType: .youtube,
                    mediaType: .video,
                    originalURL: searchQuery,
                    album: album, composer: composer, year: year
                ).withGenre(genre).withApplePlays(plays)
            }
        }
    }
    
    /// Album / composer / year for every song in the Music library, used to fill in details
    /// for songs imported before these fields existed.
    public func fetchLibraryDetails() async throws -> [AppleMusicTrackDetails] {
        let script = """
        const tracks = Application("Music").libraryPlaylists[0].tracks;
        const n = tracks.name(), ar = tracks.artist(), al = tracks.album(),
              co = tracks.composer(), yr = tracks.year(), du = tracks.duration(), ge = tracks.genre(), pc = tracks.playedCount(), da = tracks.dateAdded();
        const list = [];
        for (let i = 0; i < n.length; i++) {
            list.push({ name: n[i] || "", artist: ar[i] || "", album: al[i] || "",
                        composer: co[i] || "", year: yr[i] || 0, duration: du[i] || 0, genre: ge[i] || "", plays: pc[i] || 0, added: da[i] ? da[i].getTime() : 0 });
        }
        JSON.stringify(list);
        """
        let output = try await runJXA(script: script)
        guard let data = output.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return jsonArray.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            return AppleMusicTrackDetails(
                name: name,
                artist: (item["artist"] as? String) ?? "",
                album: (item["album"] as? String) ?? "",
                composer: (item["composer"] as? String) ?? "",
                year: (item["year"] as? Int) ?? 0,
                duration: (item["duration"] as? Double) ?? 0,
                genre: (item["genre"] as? String) ?? "",
                plays: (item["plays"] as? Int) ?? 0,
                dateAdded: (item["added"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            )
        }
    }
    
    private func runJXA(script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        try process.run()
        
        // Drain the pipes before waiting: large playlists produce more output than the pipe
        // buffer holds, and osascript would block forever waiting for us to read it.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8) ?? "AppleScript error"
            throw NSError(domain: "AppleMusicService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
