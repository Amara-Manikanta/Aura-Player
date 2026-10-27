import Foundation

/// Finds a photo for a singer or artist (via Deezer's free artist search) and remembers it on disk,
/// so each name is looked up once, even across launches.
public actor ArtistPhotoService {
    public static let shared = ArtistPhotoService()
    
    /// normalized name → photo URL, or "" when no photo was found
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var nextSlot = Date.distantPast
    private let fileURL: URL
    
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AuraPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("artist_photos.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = saved
        } else if let bundled = Bundle.main.url(forResource: "artist_photos", withExtension: "json"),
                  let data = try? Data(contentsOf: bundled),
                  let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            // First launch: start with everything the Mac app already found
            cache = saved
        }
    }
    
    /// Photo URL for an artist name such as "Sid Sriram" or "Zedd & Katy Perry" (looks up the first name).
    public func photoURL(for artistName: String) async -> URL? {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.normalize(name)
        guard key.count >= 2 else { return nil }
        
        if let cached = cache[key] { return cached.isEmpty ? nil : URL(string: cached) }
        if let running = inFlight[key] { return await running.value }
        
        let task = Task<URL?, Never> { await self.fetch(name: name, key: key) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
    
    private func fetch(name: String, key: String) async -> URL? {
        // Deezer allows ~50 requests per 5 seconds: space requests out
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(0.15)
        if slot > now { try? await Task.sleep(nanoseconds: UInt64(slot.timeIntervalSince(now) * 1_000_000_000)) }
        
        guard var components = URLComponents(string: "https://api.deezer.com/search/artist") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "8")]
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["data"] as? [[String: Any]] else {
                return nil // network trouble: don't remember a miss, try again later
            }
            
            // Only accept an artist whose name really matches; the most popular one wins
            let best = results
                .filter { Self.namesMatch(key, Self.normalize($0["name"] as? String ?? "")) }
                .max { ($0["nb_fan"] as? Int ?? 0) < ($1["nb_fan"] as? Int ?? 0) }
            
            var found = ""
            if let best {
                let picture = (best["picture_xl"] as? String) ?? (best["picture_big"] as? String) ?? ""
                // Deezer uses an empty image path for artists without a photo
                if !picture.isEmpty, !picture.contains("/images/artist//") { found = picture }
            }
            cache[key] = found
            save()
            return found.isEmpty ? nil : URL(string: found)
        } catch {
            return nil
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    // MARK: - Name handling
    
    /// "Zedd & Katy Perry" → "Zedd", "Hariharan, Shankar Mahadevan" → "Hariharan"
    static func firstArtist(of name: String) -> String {
        var n = name
        if let r = n.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) { n.removeSubrange(r) }
        for separator in [" & ", ",", " feat.", " feat ", " ft.", " ft ", " featuring ", " x ", " and ", ";"] {
            if let r = n.range(of: separator, options: .caseInsensitive) { n = String(n[..<r.lowerBound]) }
        }
        return n.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Lowercase letters and digits only, so "A.R. Rahman" == "A. R. Rahman".
    static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased().filter { $0.isLetter || $0.isNumber }
    }
    
    /// Same artist: equal, or one is the other plus a short extra ("Sid Sriram" vs "Sid Sriram Official").
    static func namesMatch(_ wanted: String, _ found: String) -> Bool {
        guard !wanted.isEmpty, !found.isEmpty else { return false }
        if wanted == found { return true }
        let (short, long) = wanted.count <= found.count ? (wanted, found) : (found, wanted)
        return short.count >= 5 && long.contains(short) && Double(short.count) / Double(long.count) >= 0.75
    }
}
