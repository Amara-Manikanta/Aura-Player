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
        let cleaned = MetadataCleaner.clean(title: title, artist: artist)
        let cleanTitle = cleaned.cleanTitle
        let cleanArtist = cleaned.primaryArtist
        let cacheKey = "\(cleanArtist)-\(cleanTitle)".lowercased()
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // 1. Try exact match first
        if let lyrics = await fetchFromLrcLib(artist: cleanArtist, title: cleanTitle, duration: duration) {
            cache[cacheKey] = lyrics
            return lyrics
        }
        
        // 2. Try search fallback
        if let lyrics = await searchLrcLib(query: "\(cleanTitle) \(cleanArtist)") {
            cache[cacheKey] = lyrics
            return lyrics
        }
        
        // 3. Try JioSaavn fallback
        if let lyrics = await fetchFromJioSaavn(artist: cleanArtist, title: cleanTitle) {
            cache[cacheKey] = lyrics
            return lyrics
        }
        
        // 4. Try Lyrics.ovh fallback
        if let lyrics = await fetchFromLyricsOvh(artist: cleanArtist, title: cleanTitle) {
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
            request.setValue("AuraPlayerIOS/1.0", forHTTPHeaderField: "User-Agent")
            
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
            request.setValue("AuraPlayerIOS/1.0", forHTTPHeaderField: "User-Agent")
            
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
    
    private func fetchFromJioSaavn(artist: String, title: String) async -> SongLyrics? {
        guard let query = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        guard let searchUrl = URL(string: "https://www.jiosaavn.com/api.php?__call=autocomplete.get&_format=json&_marker=0&cc=in&includeMetaTags=1&query=\(query)") else { return nil }
        
        do {
            var searchReq = URLRequest(url: searchUrl)
            searchReq.timeoutInterval = 6
            searchReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (searchData, _) = try await URLSession.shared.data(for: searchReq)
            guard let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let songsObj = searchJson["songs"] as? [String: Any],
                  let songsData = songsObj["data"] as? [[String: Any]],
                  let firstSong = songsData.first,
                  let songUrlStr = firstSong["url"] as? String,
                  let songUrl = URL(string: songUrlStr) else { return nil }
                  
            var pageReq = URLRequest(url: songUrl)
            pageReq.timeoutInterval = 6
            pageReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (pageData, _) = try await URLSession.shared.data(for: pageReq)
            guard let html = String(data: pageData, encoding: .utf8) else { return nil }
            
            let pattern = #"\"lyrics\":\{(\"content\":\".*?\"),\"copyright\""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(match.range(at: 1), in: html) else { return nil }
                  
            let jsonFragment = "{" + String(html[r]) + "}"
            guard let fragmentData = jsonFragment.data(using: .utf8),
                  let fragJson = try? JSONSerialization.jsonObject(with: fragmentData) as? [String: Any],
                  let content = fragJson["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                  
            let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            
            let synced = lines.enumerated().map { i, text in
                LyricLine(time: 15.0 + Double(i) * 5.0, text: text)
            }
            return SongLyrics(plainLyrics: content, syncedLines: synced)
        } catch {
            return nil
        }
    }
    
    private func fetchFromLyricsOvh(artist: String, title: String) async -> SongLyrics? {
        var coreTitle = title
        if let r = coreTitle.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) { coreTitle.removeSubrange(r) }
        coreTitle = coreTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let firstArt = ArtistPhotoService.firstArtist(of: artist)
        guard let encArt = firstArt.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encTitle = coreTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encArt)/\(encTitle)") else { return nil }
              
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyricsText = json["lyrics"] as? String,
                  lyricsText.count > 30 else { return nil }
                  
            let lines = lyricsText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            let synced = lines.enumerated().map { i, text in
                LyricLine(time: 15.0 + Double(i) * 5.0, text: text)
            }
            return SongLyrics(plainLyrics: lyricsText, syncedLines: synced)
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
}
