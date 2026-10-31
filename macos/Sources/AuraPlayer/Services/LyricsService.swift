import Foundation

public struct LyricLine: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let time: TimeInterval
    public let text: String
    
    public init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct SongLyrics: Sendable {
    public let plainLyrics: String?
    public let syncedLines: [LyricLine]
    public var isSynced: Bool { !syncedLines.isEmpty }
    
    public init(plainLyrics: String? = nil, syncedLines: [LyricLine] = []) {
        self.plainLyrics = plainLyrics
        self.syncedLines = syncedLines
    }
}

public actor LyricsService {
    public static let shared = LyricsService()
    
    private var cache: [String: SongLyrics] = [:]
    
    private init() {}
    
    public func fetchLyrics(artist: String, title: String, duration: TimeInterval = 0) async -> SongLyrics? {
        if let custom = CustomLyricsFile.lyrics(title: title, artist: artist) { return custom }
        let cleanTitle = sanitize(title)
        let cleanArtist = sanitize(artist)
        let cacheKey = "\(cleanArtist)-\(cleanTitle)".lowercased()
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Try exact match first
        if let lyrics = await fetchFromLrcLib(artist: cleanArtist, title: cleanTitle, duration: duration) {
            cache[cacheKey] = lyrics
            return lyrics
        }
        
        // Try search fallback
        if let lyrics = await searchLrcLib(query: "\(cleanTitle) \(cleanArtist)") {
            cache[cacheKey] = lyrics
            return lyrics
        }
        
        return nil
    }
    
    private func fetchFromLrcLib(artist: String, title: String, duration: TimeInterval) async -> SongLyrics? {
        guard var components = URLComponents(string: "https://lrclib.net/api/get") else { return nil }
        
        var queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("AuraPlayer/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            let plain = json["plainLyrics"] as? String
            let synced = json["syncedLyrics"] as? String
            
            let parsedSynced = parseLrc(synced)
            return SongLyrics(plainLyrics: plain, syncedLines: parsedSynced)
        } catch {
            return nil
        }
    }
    
    private func searchLrcLib(query: String) async -> SongLyrics? {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("AuraPlayer/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
            
            guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first else { return nil }
            
            let plain = first["plainLyrics"] as? String
            let synced = first["syncedLyrics"] as? String
            
            let parsedSynced = parseLrc(synced)
            return SongLyrics(plainLyrics: plain, syncedLines: parsedSynced)
        } catch {
            return nil
        }
    }
    
    private func parseLrc(_ lrc: String?) -> [LyricLine] {
        guard let lrc = lrc, !lrc.isEmpty else { return [] }
        var result: [LyricLine] = []
        
        let lines = lrc.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            
            if let closingBracket = trimmed.firstIndex(of: "]") {
                let timeStr = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
                let text = String(trimmed[trimmed.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
                
                if let seconds = parseTimestamp(timeStr) {
                    result.append(LyricLine(time: seconds, text: text))
                }
            }
        }
        
        return result.sorted { $0.time < $1.time }
    }
    
    private func parseTimestamp(_ ts: String) -> TimeInterval? {
        let parts = ts.components(separatedBy: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
    
    private func sanitize(_ string: String) -> String {
        // Strip common clutter like (Official Video), [HQ], etc.
        var s = string
        let regexPatterns = [
            "\\(Official Video\\)",
            "\\(Official Audio\\)",
            "\\(Lyrics\\)",
            "\\[Official Video\\]",
            "\\[HQ\\]",
            "\\(From \".*\"\\)",
            "\\(Lyric Video\\)"
        ]
        for pattern in regexPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

