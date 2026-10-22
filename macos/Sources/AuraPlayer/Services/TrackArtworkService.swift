import Foundation

/// Finds the album cover for a song (Apple's free iTunes search) and remembers it on disk,
/// so every song shows artwork on every page after its first lookup.
public actor TrackArtworkService {
    public static let shared = TrackArtworkService()
    
    /// "title|artist" → cover URL, or "" when none was found
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var nextSlot = Date.distantPast
    private var unsavedChanges = 0
    private let fileURL: URL
    
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AuraPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("track_artwork.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = saved
        }
    }
    
    /// Cover already known for this song, without any network call.
    public func cachedCover(for track: MediaTrack) -> URL? {
        guard let value = cache[Self.key(for: track)], !Self.isMiss(value) else { return nil }
        return URL(string: value)
    }
    
    public func cover(for track: MediaTrack) async -> URL? {
        let key = Self.key(for: track)
        if let cached = cache[key] {
            if Self.isMiss(cached) {
                // Misses are retried after a day (a wrong match or an outage shouldn't stick forever)
                if !Self.missExpired(cached) { return nil }
            } else {
                return URL(string: cached)
            }
        }
        if let running = inFlight[key] { return await running.value }
        
        let task = Task<URL?, Never> { await self.fetch(track: track, key: key) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
    
    // MARK: - Lookup
    
    private func fetch(track: MediaTrack, key: String) async -> URL? {
        let title = track.coreTitle
        let artist = ArtistPhotoService.firstArtist(of: track.artist)
        guard !title.isEmpty else { return nil }
        
        var queries = ["\(title) \(artist)"]
        if let movie = track.movieName { queries.append("\(title) \(movie)") }
        queries.append(title)
        
        for q in queries {
            switch await search(q) {
            case .failure: return nil // network trouble: don't remember a miss
            case .success(let results):
                if let cover = Self.bestCover(in: results, for: track, title: title, artist: artist) {
                    remember(key, cover)
                    return URL(string: cover)
                }
            }
        }
        remember(key, "miss:\(Int(Date().timeIntervalSince1970))")
        return nil
    }
    
    static func isMiss(_ value: String) -> Bool { value.isEmpty || value.hasPrefix("miss:") }
    
    static func missExpired(_ value: String) -> Bool {
        guard value.hasPrefix("miss:"), let t = TimeInterval(value.dropFirst(5)) else { return true }
        return Date().timeIntervalSince1970 - t > 86_400
    }
    
    private enum SearchOutcome { case success([[String: Any]]), failure }
    
    /// iTunes Search API (free, no key): songs with their album artwork
    private func search(_ q: String) async -> SearchOutcome {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(0.35)
        if slot > now { try? await Task.sleep(nanoseconds: UInt64(slot.timeIntervalSince(now) * 1_000_000_000)) }
        
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return .failure }
        components.queryItems = [
            URLQueryItem(name: "term", value: q),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "12")
        ]
        guard let url = components.url else { return .failure }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure }
            return .success((json["results"] as? [[String: Any]]) ?? [])
        } catch {
            return .failure
        }
    }
    
    /// A result counts only if its title matches and its artist (or album) fits, so we never show a wrong cover.
    static func bestCover(in results: [[String: Any]], for track: MediaTrack, title: String, artist: String) -> String? {
        let wantedTitle = ArtistPhotoService.normalize(title)
        let artistWords = artist.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
        let wantedAlbum = ArtistPhotoService.normalize(MediaTrack.removingBrackets(track.album ?? ""))
        
        for item in results {
            let foundTitle = ArtistPhotoService.normalize(MediaTrack.removingBrackets(item["trackName"] as? String ?? ""))
            guard !foundTitle.isEmpty,
                  foundTitle == wantedTitle || (min(foundTitle.count, wantedTitle.count) >= 6 && (foundTitle.contains(wantedTitle) || wantedTitle.contains(foundTitle))) else { continue }
            
            let foundArtist = ArtistPhotoService.normalize(item["artistName"] as? String ?? "")
            let foundAlbum = ArtistPhotoService.normalize(MediaTrack.removingBrackets(item["collectionName"] as? String ?? ""))
            let artistFits = artistWords.contains { foundArtist.contains($0.filter { $0.isLetter || $0.isNumber }) }
            let albumFits = !wantedAlbum.isEmpty && foundAlbum.count >= 3
                && (foundAlbum == wantedAlbum || foundAlbum.contains(wantedAlbum) || wantedAlbum.contains(foundAlbum))
            guard artistFits || albumFits else { continue }
            
            if let small = item["artworkUrl100"] as? String, !small.isEmpty {
                return small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            }
        }
        return nil
    }
    
    // MARK: - Storage
    
    static func key(for track: MediaTrack) -> String {
        "\(ArtistPhotoService.normalize(track.coreTitle))|\(ArtistPhotoService.normalize(ArtistPhotoService.firstArtist(of: track.artist)))"
    }
    
    private func remember(_ key: String, _ value: String) {
        cache[key] = value
        unsavedChanges += 1
        if unsavedChanges >= 5 { save() }
        else {
            // flush soon even if fewer than 5 new lookups happen
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); await self.saveIfNeeded() }
        }
    }
    
    private func saveIfNeeded() { if unsavedChanges > 0 { save() } }
    
    private func save() {
        unsavedChanges = 0
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
