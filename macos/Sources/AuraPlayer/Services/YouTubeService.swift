import Foundation

public struct YouTubeSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let channel: String
    public let duration: TimeInterval
    public let thumbnailURL: String?
    public let url: String
    
    public var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

public actor YouTubeService {
    public static let shared = YouTubeService()
    
    private var videoIdCache: [String: String] = [:]
    private var streamURLCache: [String: (url: URL, date: Date)] = [:]
    
    private init() {}
    
    private func findYtDlpBinary() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    public func extractVideoId(from urlOrId: String) -> String? {
        let trimmed = urlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains("?") && !trimmed.contains(" ") {
            return trimmed
        }
        
        if let url = URL(string: trimmed) {
            if let host = url.host {
                if host.contains("youtu.be") {
                    return url.pathComponents.dropFirst().first
                } else if host.contains("youtube.com") {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let queryItems = components.queryItems {
                        for item in queryItems where item.name == "v" {
                            return item.value
                        }
                    }
                    if url.path.contains("/shorts/") {
                        return url.pathComponents.last
                    }
                    if url.path.contains("/embed/") {
                        return url.pathComponents.last
                    }
                }
            }
        }
        return nil
    }
    
    public func fastResolveVideoId(for queryOrUrl: String, songTitle: String? = nil, artist: String? = nil, movie: String? = nil, expectedDuration: TimeInterval? = nil, language: String? = nil) async -> String? {
        if let directId = extractVideoId(from: queryOrUrl) {
            return directId
        }
        
        let cleanQuery = queryOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(cleanQuery.lowercased())|\(language ?? "")"
        if let cached = videoIdCache[cacheKey] {
            AppLog.log("resolve", "cache hit \(cached) for \"\(cleanQuery)\"")
            return cached
        }
        
        // Prefer the ranked official-video search; fall back to scraping if yt-dlp is unavailable
        if let best = try? await bestOfficialVideo(for: cleanQuery, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language) {
            AppLog.log("resolve", "picked \(best.id) for \"\(cleanQuery)\" language=\(language ?? "-"): \(best.title)")
            videoIdCache[cacheKey] = best.id
            return best.id
        }
        
        // Fast HTTP search without launching heavy external python processes
        // Optimize search query to prioritize official music videos
        var searchQuery = cleanQuery
        let lower = cleanQuery.lowercased()
        if !lower.contains("official") && !lower.contains("music video") && !lower.contains("video song") {
            searchQuery = "\(cleanQuery) official music video"
        }
        
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return await fallbackYtDlpSearch(query: searchQuery)
        }
        
        do {
            var request = URLRequest(url: searchURL)
            request.timeoutInterval = 5
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return await fallbackYtDlpSearch(query: searchQuery)
            }
            
            let nsHtml = html as NSString
            
            // Extract all Shorts/Reels IDs in HTML to filter them out
            let shortsPattern = "/shorts/([a-zA-Z0-9_-]{11})"
            let shortsRegex = try NSRegularExpression(pattern: shortsPattern)
            let shortsMatches = shortsRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            var shortsIds = Set<String>()
            for sm in shortsMatches where sm.numberOfRanges > 1 {
                shortsIds.insert(nsHtml.substring(with: sm.range(at: 1)))
            }
            
            // Regex to find videoId and title in YouTube initial data
            let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\".*?\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}"
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            
            let disallowed = [
                "lyric", "lyrics", "lyrical", "karaoke", "slowed", "reverb",
                "8d audio", "bass boosted", "instrumental", "cover", "status",
                "reaction", "shorts", "#shorts", "#short", "reel", "reels", "#reel", "#reels",
                "1 hour", "extended", "mashup", "tiktok"
            ]
            
            for match in matches {
                if match.numberOfRanges > 2 {
                    let vid = nsHtml.substring(with: match.range(at: 1))
                    let title = nsHtml.substring(with: match.range(at: 2)).lowercased()
                    
                    if shortsIds.contains(vid) {
                        continue // Strictly discard Shorts / Reels!
                    }
                    
                    let isDisallowed = disallowed.contains { kw in
                        title.contains(kw) && !lower.contains(kw)
                    }
                    if isDisallowed {
                        continue
                    }
                    
                    videoIdCache[cleanQuery.lowercased()] = vid
                    return vid
                }
            }
            
            // Fallback to first non-short videoId
            for match in matches {
                if match.numberOfRanges > 1 {
                    let vid = nsHtml.substring(with: match.range(at: 1))
                    if !shortsIds.contains(vid) {
                        videoIdCache[cleanQuery.lowercased()] = vid
                        return vid
                    }
                }
            }
        } catch {
            return await fallbackYtDlpSearch(query: searchQuery)
        }
        
        return await fallbackYtDlpSearch(query: searchQuery)
    }
    
    /// Next-best official video when the chosen one can't be embedded. Skips every video that already
    /// failed for this track, and never falls back to an unrelated song.
    public func resolveAlternativeVideoId(
        for queryOrUrl: String,
        songTitle: String? = nil,
        artist: String? = nil,
        movie: String? = nil,
        expectedDuration: TimeInterval? = nil,
        language: String? = nil,
        excluding: Set<String>
    ) async -> String? {
        let cleanQuery = queryOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if findYtDlpBinary() != nil {
            // After a 👎 the first phrasing may be used up, so try other ways of asking for the same song
            let core = Self.coreSongTitle(songTitle ?? cleanQuery)
            let mainArtist = (artist ?? "").components(separatedBy: CharacterSet(charactersIn: "&,(")).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            var variants = [cleanQuery]
            if let movie, !movie.isEmpty { variants.append("\(core) \(movie) full video song") }
            if !mainArtist.isEmpty { variants.append("\(core) \(mainArtist) official video") }
            variants.append("\(core) video song")
            var seen = Set<String>()
            for variant in variants where seen.insert(variant.lowercased()).inserted {
                let ranked = (try? await languageAwareSearch(query: variant, limit: 12, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language)) ?? []
                if let alt = ranked.first(where: { !excluding.contains($0.id) }) {
                    AppLog.log("resolve", "alternative \(alt.id) for \"\(cleanQuery)\" via \"\(variant)\" (excluded: \(excluding.sorted())): \(alt.title)")
                    videoIdCache[cleanQuery.lowercased()] = alt.id
                    return alt.id
                }
            }
            AppLog.log("resolve", "no alternative for \"\(cleanQuery)\" (excluded: \(excluding.sorted()))")
            return nil
        }
        return await scrapeAlternativeVideoId(for: cleanQuery, excluding: excluding)
    }
    
    private func scrapeAlternativeVideoId(for cleanQuery: String, excluding: Set<String>) async -> String? {
        var searchQuery = cleanQuery
        let lower = cleanQuery.lowercased()
        if !lower.contains("official") && !lower.contains("music video") && !lower.contains("video song") {
            searchQuery = "\(cleanQuery) official music video"
        }
        
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return nil
        }
        
        do {
            var request = URLRequest(url: searchURL)
            request.timeoutInterval = 5
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }
            
            let nsHtml = html as NSString
            let shortsPattern = "/shorts/([a-zA-Z0-9_-]{11})"
            let shortsRegex = try NSRegularExpression(pattern: shortsPattern)
            let shortsMatches = shortsRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            var shortsIds = Set<String>()
            for sm in shortsMatches where sm.numberOfRanges > 1 {
                shortsIds.insert(nsHtml.substring(with: sm.range(at: 1)))
            }
            
            let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\".*?\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}"
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            
            let disallowed = [
                "lyric", "lyrics", "lyrical", "karaoke", "slowed", "reverb",
                "8d audio", "bass boosted", "instrumental", "cover", "status",
                "reaction", "shorts", "#shorts", "#short", "reel", "reels", "#reel", "#reels",
                "1 hour", "extended", "mashup", "tiktok"
            ]
            
            for match in matches {
                if match.numberOfRanges > 2 {
                    let vid = nsHtml.substring(with: match.range(at: 1))
                    let title = nsHtml.substring(with: match.range(at: 2)).lowercased()
                    
                    if excluding.contains(vid) || shortsIds.contains(vid) { continue }
                    
                    let isDisallowed = disallowed.contains { kw in
                        title.contains(kw) && !lower.contains(kw)
                    }
                    if isDisallowed { continue }
                    
                    videoIdCache[cleanQuery.lowercased()] = vid
                    return vid
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func fallbackYtDlpSearch(query: String) async -> String? {
        guard let binary = findYtDlpBinary() else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--dump-single-json",
            "--no-warnings",
            "--default-search", "ytsearch5:",
            "--no-playlist",
            query
        ]
        
        let stdout = Pipe()
        process.standardOutput = stdout
        try? process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        // Read before waiting: yt-dlp output can exceed the pipe buffer and would block forever.
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            return nil
        }
        
        let disallowed = ["lyric", "lyrics", "lyrical", "karaoke", "slowed", "reverb", "8d audio", "bass boosted", "cover", "status"]
        for entry in entries {
            guard let id = entry["id"] as? String,
                  let title = (entry["title"] as? String)?.lowercased() else { continue }
            if disallowed.contains(where: { title.contains($0) }) && !query.lowercased().contains("lyric") {
                continue
            }
            videoIdCache[query.lowercased()] = id
            return id
        }
        
        if let first = entries.first, let id = first["id"] as? String {
            videoIdCache[query.lowercased()] = id
            return id
        }
        return nil
    }
    
    public func fetchTrackInfo(urlOrQuery: String) async throws -> MediaTrack {
        guard let binary = findYtDlpBinary() else {
            throw NSError(domain: "YouTubeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found. Please install via 'brew install yt-dlp'."])
        }
        
        let isDirectURL = urlOrQuery.lowercased().hasPrefix("http://") || urlOrQuery.lowercased().hasPrefix("https://")
        let target = isDirectURL ? urlOrQuery : "ytsearch1:\(urlOrQuery)"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--dump-single-json",
            "--no-warnings",
            "--no-playlist",
            "--no-check-certificates",
            target
        ]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        // Read before waiting: yt-dlp output can exceed the pipe buffer and would block forever.
        process.waitUntilExit()
        guard !data.isEmpty else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown yt-dlp error"
            throw NSError(domain: "YouTubeService", code: 2, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YouTubeService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse YouTube metadata"])
        }
        
        let item: [String: Any]
        if let entries = json["entries"] as? [[String: Any]], let first = entries.first {
            item = first
        } else {
            item = json
        }
        
        let title = (item["title"] as? String) ?? "YouTube Video"
        let artist = (item["uploader"] as? String) ?? (item["channel"] as? String) ?? "Unknown Artist"
        let duration = (item["duration"] as? Double) ?? 0.0
        let videoId = (item["id"] as? String) ?? ""
        let webpageUrl = (item["webpage_url"] as? String) ?? "https://www.youtube.com/watch?v=\(videoId)"
        
        var thumbnailURL: String? = item["thumbnail"] as? String
        if thumbnailURL == nil && !videoId.isEmpty {
            thumbnailURL = "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
        }
        
        return MediaTrack(
            title: title,
            artist: artist,
            duration: duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: webpageUrl,
            thumbnailURL: thumbnailURL,
            youtubeId: videoId
        )
    }
    
    public func resolveDirectStreamURL(for url: String, audioOnly: Bool = false) async throws -> URL {
        let cacheKey = "\(url)-\(audioOnly)".lowercased()
        if let cached = streamURLCache[cacheKey], Date().timeIntervalSince(cached.date) < 10800 { // 3 hours
            return cached.url
        }
        
        guard let binary = findYtDlpBinary() else {
            throw NSError(domain: "YouTubeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found"])
        }
        
        // For audio: format 140 (AAC) or best audio is 100% reliable across all YouTube tracks
        let formatArg = "140/ba[ext=m4a]/ba/best"
        
        var target = url
        let isDirectURL = url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://")
        if !isDirectURL {
            if let vid = await fastResolveVideoId(for: url) {
                target = "https://www.youtube.com/watch?v=\(vid)"
            } else {
                target = "ytsearch1:\(url)"
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "-g",
            "-f", formatArg,
            "--no-check-certificates",
            target
        ]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        // Read before waiting: yt-dlp output can exceed the pipe buffer and would block forever.
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard let firstLine = output.components(separatedBy: .newlines).first,
              let streamURL = URL(string: firstLine), !firstLine.isEmpty else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Stream extraction failed"
            throw NSError(domain: "YouTubeService", code: 4, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        
        streamURLCache[cacheKey] = (url: streamURL, date: Date())
        return streamURL
    }
    
    /// - Parameters:
    ///   - songTitle: when resolving a known track, its song name; results that don't contain it are dropped.
    ///   - expectedDuration: when known (e.g. from Apple Music), videos close to this length rank higher.
    public func searchVideos(query: String, limit: Int = 8, songTitle: String? = nil, artist: String? = nil, movie: String? = nil, expectedDuration: TimeInterval? = nil, language: String? = nil) async throws -> [YouTubeSearchResult] {
        guard let binary = findYtDlpBinary() else {
            throw NSError(domain: "YouTubeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found. Please install via 'brew install yt-dlp'."])
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // --flat-playlist reads only the search results page instead of fully extracting
        // every video, which takes searches from ~18s down to ~1s.
        process.arguments = [
            "--dump-single-json",
            "--no-warnings",
            "--flat-playlist",
            "ytsearch\(max(limit * 2, 15)):\(Self.officialSearchQuery(for: query))"
        ]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        // Read before waiting: yt-dlp output can exceed the pipe buffer and would block forever.
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else {
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "YouTubeService", code: 4, userInfo: [NSLocalizedDescriptionKey: (errMsg?.isEmpty == false ? errMsg! : "YouTube search failed")])
        }
        
        let candidates: [YouTubeSearchResult] = entries.compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String else { return nil }
            let channel = (item["uploader"] as? String) ?? (item["channel"] as? String) ?? "YouTube"
            let duration = (item["duration"] as? Double) ?? 0.0
            let thumb = (item["thumbnail"] as? String) ?? "https://img.youtube.com/vi/\(id)/hqdefault.jpg"
            let url = (item["webpage_url"] as? String) ?? (item["url"] as? String) ?? "https://www.youtube.com/watch?v=\(id)"
            return YouTubeSearchResult(id: id, title: title, channel: channel, duration: duration, thumbnailURL: thumb, url: url)
        }
        return Array(Self.rankOfficialVideos(candidates, query: query, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language).prefix(limit))
    }
    
    // MARK: - New Releases
    
    public struct NewRelease: Identifiable, Hashable, Sendable {
        public var id: String { video.id }
        public let video: YouTubeSearchResult
        public let views: Int
    }
    
    public enum ReleasePeriod: String, CaseIterable, Sendable {
        case week = "This Week"
        case month = "This Month"
        /// YouTube search filter: uploaded this week / this month, videos only
        var filter: String { self == .week ? "EgQIAxAB" : "EgQIBBAB" }
    }
    
    private var newReleaseCache: [String: (date: Date, items: [NewRelease])] = [:]
    
    /// Songs uploaded recently in a language, official labels and real videos first.
    public func newReleases(language: String, period: ReleasePeriod, forceRefresh: Bool = false) async throws -> [NewRelease] {
        let cacheKey = "\(language)|\(period.rawValue)"
        if !forceRefresh, let cached = newReleaseCache[cacheKey], Date().timeIntervalSince(cached.date) < 1800 {
            return cached.items
        }
        guard let binary = findYtDlpBinary() else {
            throw NSError(domain: "YouTubeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found. Please install via 'brew install yt-dlp'."])
        }
        let lang = language.lowercased()
        let queries: [String]
        switch lang {
        case "english": queries = ["new official music video", "official music video new song"]
        case "hindi": queries = ["hindi new song official video", "bollywood new video song"]
        default: queries = ["\(lang) new video song", "\(lang) latest song official video"]
        }
        
        var seen = Set<String>()
        var items: [NewRelease] = []
        for q in queries {
            guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
            // English: ask YouTube for US results, otherwise it serves Indian songs to an Indian location
            let region = lang == "english" ? "&gl=US&hl=en" : ""
            let url = "https://www.youtube.com/results?search_query=\(encoded)&sp=\(period.filter)\(region)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["--dump-single-json", "--no-warnings", "--flat-playlist", "--playlist-end", "40", url]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else { continue }
            
            for e in entries {
                guard let id = e["id"] as? String, let title = e["title"] as? String, seen.insert(id).inserted else { continue }
                let duration = (e["duration"] as? Double) ?? 0
                let video = YouTubeSearchResult(
                    id: id,
                    title: title,
                    channel: (e["channel"] as? String) ?? (e["uploader"] as? String) ?? "YouTube",
                    duration: duration,
                    thumbnailURL: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                    url: "https://www.youtube.com/watch?v=\(id)"
                )
                guard Self.looksLikeNewSong(video, language: lang) else { continue }
                items.append(NewRelease(video: video, views: (e["view_count"] as? Int) ?? 0))
            }
        }
        
        // Label uploads and proper videos first, then by views
        let ranked = items.sorted { Self.releaseScore($0) > Self.releaseScore($1) }
        newReleaseCache[cacheKey] = (Date(), ranked)
        AppLog.log("releases", "\(language) \(period.rawValue): \(ranked.count) songs")
        return ranked
    }
    
    /// Keeps real songs; drops trailers, teasers, jukeboxes, covers, reels, events and other languages.
    static func looksLikeNewSong(_ v: YouTubeSearchResult, language: String) -> Bool {
        let t = v.title.lowercased()
        if v.url.contains("/shorts/") || v.duration < 90 || v.duration > 480 { return false }
        let junk = ["trailer", "teaser", "promo", "glimpse", "jukebox", "reaction", "cover", "status", "#shorts", "reel",
                    "making", "interview", "speech", "launch", "event", "karaoke", "slowed", "reverb", "8d", "bgm",
                    "scene", "full movie", "episode", "news", "review", "remix", "mashup", "dance video", "tutorial",
                    "behind the scenes", "bts", "podcast", "live stream", "nonstop", "back to back", "audio jukebox",
                    "performance", "pooja", "puja ceremony", "press meet", "ai song", "ai generated", "fan made"]
        if junk.contains(where: { t.contains($0) }) { return false }
        // Old hits re-uploaded as "8K Video Song" / remasters / classics aren't new releases
        let reissue = ["8k", "4k", "remaster", "classic", "classics", "evergreen", "superhit", "super hit", " hits", "old song",
                       "retro", "90s", "80s", "70s", "all time", "best of", "top 10", "top 20"]
        if reissue.contains(where: { t.contains($0) }) { return false }
        // Must look like a song (drops movie promos such as "Ranabaali | Truth 1 - …")
        let songWords = ["song", "video", "lyric", "music", "audio", "single", "official"]
        if !songWords.contains(where: { t.contains($0) }) { return false }
        let videoLang = videoLanguage(title: v.title, channel: v.channel)
        if language == "english" {
            // English list: nothing tagged with an Indian language, from an Indian label, or regional
            if videoLang != nil { return false }
            let c = v.channel.lowercased()
            let regional = ["bhojpuri", "santali", "bengali", "bangla", "odia", "assamese", "nepali", "kokborok",
                            "garo", "haryanvi", "rajasthani", "gujarati", "marathi", "bollywood", "desi", "sambalpuri",
                            "khasi", "mizo", "manipuri", "bodo", "pahadi", "garhwali", "kumaoni", "chhattisgarhi"]
            if regional.contains(where: { t.contains($0) || c.contains($0) }) { return false }
            if c.contains("india") || c.contains("saregama") { return false }
        } else if let videoLang, videoLang != language {
            // Other Indian languages' versions don't belong in this language's list
            return false
        }
        return true
    }
    
    static func releaseScore(_ r: NewRelease) -> Double {
        let t = r.video.title.lowercased(), c = r.video.channel.lowercased()
        var score = log10(Double(max(r.views, 1)))          // 1k views → 3, 1M → 6
        let labels = ["vevo", "t-series", "sony music", "zee music", "tips", "saregama", "aditya music", "lahari",
                      "mango music", "think music", "yrf", "speed records", "times music", "anand audio", "muzik247",
                      "mythri", "geetha arts", "sun tv", "divo", "junglee", "eros now",
                      "atlantic", "republic records", "interscope", "columbia", "rca records", "capitol",
                      "warner", "island records", "def jam", "universal music group"]
        if labels.contains(where: { c.contains($0) }) { score += 3 }
        // The artist's own channel: "Taylor Swift" posting "Taylor Swift - Patient Zero"
        let channelName = c.replacingOccurrences(of: " official", with: "").replacingOccurrences(of: "vevo", with: "")
            .trimmingCharacters(in: .whitespaces)
        if channelName.count >= 3 && t.hasPrefix(channelName) { score += 3 }
        if c.contains("classics") { score -= 3 }
        if ["video song", "official video", "music video", "full video"].contains(where: { t.contains($0) }) { score += 2 }
        if t.contains("lyric") { score -= 1.5 }
        if t.contains("audio") { score -= 1 }
        return score
    }
    
    /// The single most likely official video song for a typed song name.
    public func bestOfficialVideo(for query: String, songTitle: String? = nil, artist: String? = nil, movie: String? = nil, expectedDuration: TimeInterval? = nil, language: String? = nil) async throws -> YouTubeSearchResult? {
        try await languageAwareSearch(query: query, limit: 1, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language).first
    }
    
    /// Song name without "(From "Movie")", "[Remastered]" or " - Live" style suffixes.
    static func coreSongTitle(_ title: String) -> String {
        var t = title
        if let r = t.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) { t.removeSubrange(r) }
        // "Song - Remastered 2011" → "Song", but keep "Lokah - Chapter 1: Chandra Trailer Theme" whole
        if let r = t.range(of: " - ", options: .backwards) {
            let suffix = t[r.upperBound...].lowercased()
            let versionWords = ["remaster", "live", "version", "mix", "edit", "from", "single", "remix",
                                "acoustic", "reprise", "unplugged", "radio", "mono", "stereo", "bonus"]
            if versionWords.contains(where: { suffix.contains($0) }) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Official Video Ranking
    
    /// Normalizes romanized Indian-language spellings so variants compare equal:
    /// drops spaces/punctuation, folds long vowels and aspirated consonants, collapses doubled letters.
    static func translit(_ s: String) -> String {
        var x = s.lowercased().filter { $0.isLetter || $0.isNumber }
        for (from, to) in [("aa", "a"), ("ee", "i"), ("ii", "i"), ("oo", "u"), ("uu", "u"), ("ou", "u"),
                           ("th", "t"), ("dh", "d"), ("bh", "b"), ("kh", "k"), ("gh", "g"),
                           ("sh", "s"), ("ph", "f"), ("w", "v"), ("z", "j")] {
            x = x.replacingOccurrences(of: from, with: to)
        }
        var out = ""
        for c in x where out.last != c { out.append(c) }
        return out
    }
    
    /// Language of a video, from its title ("Srivalli (Hindi)") or, since official dubbed uploads
    /// often don't say, from the label that uploaded it (T-Series → Hindi, Aditya Music → Telugu).
    static func videoLanguage(title: String, channel: String) -> String? {
        let t = title.lowercased(), c = channel.lowercased()
        if let lang = MediaTrack.indianLanguages.first(where: { t.contains($0) }) { return lang }
        if let lang = MediaTrack.indianLanguages.first(where: { c.contains($0) }) { return lang }
        let labels: [(String, [String])] = [
            ("telugu", ["aditya music", "mango music", "shalimar", "sri balaji", "telugu filmnagar", "geetha arts", "mythri", "suresh productions"]),
            ("tamil", ["think music", "sun tv", "divo"]),
            ("kannada", ["anand audio", "pmusic", "d beats"]),
            ("malayalam", ["muzik247", "manorama music", "east coast", "wayfarer"]),
            ("punjabi", ["apna punjab", "speed records", "white hill", "geet mp3", "jass records"]),
            ("hindi", ["saregama music", "t-series", "zee music", "tips", "yrf", "yash raj", "sony music india", "goldmines", "eros now", "venus", "shemaroo", "dharma", "red chillies"])
        ]
        for (lang, names) in labels where names.contains(where: { c.contains($0) }) { return lang }
        return nil
    }
    
    /// Finds the song in `language`: tries the normal search first (official originals rank best that
    /// way); only if its top result is in another language, searches again with the language name added.
    /// Falls back to the original when no version in that language exists.
    func languageAwareSearch(query: String, limit: Int, songTitle: String?, artist: String?, movie: String?, expectedDuration: TimeInterval?, language: String?) async throws -> [YouTubeSearchResult] {
        let plain = try await searchVideos(query: query, limit: limit, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language)
        guard let language, !query.lowercased().contains(language) else { return plain }
        if let top = plain.first, Self.videoLanguage(title: top.title, channel: top.channel) == language {
            return plain
        }
        let dubbed = try await searchVideos(query: "\(query) \(language)", limit: limit, songTitle: songTitle, artist: artist, movie: movie, expectedDuration: expectedDuration, language: language)
        if let top = dubbed.first, Self.videoLanguage(title: top.title, channel: top.channel) == language {
            AppLog.log("search", "using \(language) version for \"\(query)\": \(top.title)")
            return dubbed
        }
        AppLog.log("search", "no \(language) version for \"\(query)\", using original")
        return plain
    }
    
    /// Biases the search toward video songs unless the user already said what they want.
    static func officialSearchQuery(for query: String) -> String {
        let lower = query.lowercased()
        let intentWords = ["video", "audio", "lyric", "official", "live", "cover", "karaoke", "remix", "jukebox"]
        return intentWords.contains(where: { lower.contains($0) }) ? query : "\(query) video song"
    }
    
    /// Drops Shorts/reels, lyric videos, audio uploads, loops etc., then orders the rest so the
    /// original video song from the label or artist comes first.
    static func rankOfficialVideos(_ results: [YouTubeSearchResult], query: String, songTitle: String? = nil, artist: String? = nil, movie: String? = nil, expectedDuration: TimeInterval? = nil, language: String? = nil) -> [YouTubeSearchResult] {
        let q = query.lowercased()
        let fillerWords: Set<String> = ["video", "song", "songs", "official", "full", "music", "the", "a", "-", "|"]
        let queryWords = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !fillerWords.contains($0) }
        
        // Rejected outright unless the user typed that word themselves
        let rejected = [
            "lyric", "lyrics", "lyrical", "letra", "karaoke", "slowed", "reverb", "8d", "bass boosted",
            "cover", "status", "reaction", "#shorts", "shorts", "#short", "reel", "reels", "tiktok",
            "mashup", "loop", "minutes version", "hour", "extended", "ringtone", "bgm", "instrumental",
            "whatsapp", "kidz bop", "mmv", "amv", "nightcore", "choreography", "dance cover", "indian idol",
            "traducida", "traducción", "traduccion", "translated", "sub español", "subtitulado", "legendado",
            "freestyle", "reversed", "just dance", "behind the scenes", "bts", "pre wedding", "wedding video", "launch event", "song launch", "audio launch", "speech", "interview", "press meet", "pre release",
            "pre-release", "full movie", "interval bgm", "movie scene", "scenes", "making video", "fan made"
        ]
        // Allowed but pushed down
        let penalized = [
            "retrowave", "lofi", "lo-fi", " mix", "audio", "jukebox", "live", "performs", "performance", "teaser", "trailer", "promo",
            "promotional", "making", "behind the scenes", "remix", "fan made"
        ]
        let officialTitle = [
            "official video", "official music video", "(official)", "[official]", "official visualizer", "video song", "full video", "music video",
            "official 4k", "8k video", "4k video", "video telugu", "video tamil", "video hindi", "video |", "(video)"
        ]
        let officialChannels = [
            "vevo", "volume", "aditya music", "sony music", "t-series", "lahari", "saregama", "mango music",
            "think music", "zee music", "tips", "sun tv", "divo", "junglee", "speed records",
            "eros now", "yrf", "times music", "muzik247", "goldmines", "venus", "shemaroo",
            "madhura audio", "anand audio", "sri balaji", "geetha arts", "mythri", "shalimar",
            "suresh productions", "volga", "rajshri", "ultra", "telugu filmnagar", "yrf", "yash raj",
            "dharma", "red chillies", "excel", "official"
        ]
        // Fan re-uploads (upscales, 60fps edits) rank below the original label upload
        let reuploadMarkers = ["upscale", "60fps", "8k songs", "remastered", "hdr edit", "audiophile", "high quality"]
        
        let queryKey = translit(queryWords.joined())
        let songWords = songTitle.map { coreSongTitle($0).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) } ?? []
        let songKey = translit(songWords.joined())
        // Ignore 1-2 letter words ("o", "re") when matching: they occur inside almost any title
        // and generic words ("God Father Theme" vs the video "God Father - Title Song") aren't required
        let genericSongWords: Set<String> = ["theme", "title", "song", "songs", "track", "version", "the", "and"]
        let realSongWords = songWords.filter { $0.count >= 3 && !genericSongWords.contains($0) }
        let significantSongWords = realSongWords.isEmpty ? songWords : realSongWords
        let movieWords = (movie ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        // Main artist ("Swedish House Mafia" from "Swedish House Mafia & John Martin")
        let mainArtist = (artist ?? "").lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "&,(")).first?
            .replacingOccurrences(of: " feat.", with: "").trimmingCharacters(in: .whitespaces) ?? ""
        // Words of the artist's name, so "SS Thaman" matches "Thaman S" and "Swedish House Mafia" matches its channel
        let artistWords = mainArtist.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
        // Every credited artist ("Zedd & Katy Perry" → [zedd], [katy, perry]); the channel may be either one
        let artistNames: [[String]] = (artist ?? "").lowercased()
            .replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "&,"))
            .map { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 } }
            .filter { !$0.isEmpty }
        
        var scored: [(result: YouTubeSearchResult, score: Double)] = []
        for (index, r) in results.enumerated() {
            let title = r.title.lowercased()
            let channel = r.channel.lowercased()
            
            if r.url.contains("/shorts/") { continue }
            if r.duration > 0 && (r.duration < 60 || r.duration > 900) { continue }
            // The artist's own channel (not a "- Topic" art-track channel)
            let isArtistChannel = !channel.contains("topic")
                && artistNames.contains { name in name.allSatisfy { translit(channel).contains(translit($0)) } }
            // Songs with no music video often have an "Official Lyric Video" on the artist's channel: that's the real one
            let officialLyricByArtist = isArtistChannel && title.contains("official lyric")
            if rejected.contains(where: { title.contains($0) && !q.contains($0) }) && !officialLyricByArtist { continue }
            
            var score = 0.0
            
            // Relevance: the typed words should appear in the title, ignoring spacing and
            // transliteration differences ("valukanuladana" ~ "Vaalu Kanuladaanaa").
            let titleKey = translit(title)
            let matched = queryWords.filter { titleKey.contains(translit($0)) }.count
            if !songWords.isEmpty {
                // Known track: the song name carries the relevance; other words (movie, singers) add a little.
                // Actor names like "Pawan Kalyan" appear in every song of a movie, so they mustn't dominate.
                let songMatched = significantSongWords.filter { titleKey.contains(translit($0)) }.count
                let extraMatched = queryWords.filter { w in !songWords.contains(w) && titleKey.contains(translit(w)) }.count
                score += 6 * Double(songMatched) / Double(significantSongWords.count) + min(1.5, 0.5 * Double(extraMatched))
            } else if !queryWords.isEmpty {
                score += 6 * Double(matched) / Double(queryWords.count)
            }
            if !queryWords.isEmpty {
                if matched == 0 { score -= 10 } // unrelated song that only matched on "video song"
                if titleKey.contains(queryKey) { score += 2 }
                // Song name in the first part of the title, not just as the movie/album name later on
                let lead = title.split(whereSeparator: { "|(".contains($0) }).first.map(String.init) ?? title
                let leadKey = translit(lead)
                if queryWords.contains(where: { leadKey.contains(translit($0)) }) { score += 3 }
                if leadKey.hasPrefix(queryKey) { score += 1 }
            }
            if reuploadMarkers.contains(where: { title.contains($0) || channel.contains($0) }) { score -= 3 }
            // YouTube's auto-generated uploads have the bare song name as the whole title and show a still
            // image; the real music video almost always has more in its title (movie, cast, "Video Song").
            // (the artist's own channel, e.g. "Michael Giacchino" uploading "The Park is Closed", is the real thing)
            if !songKey.isEmpty, titleKey == songKey, !isArtistChannel, !officialTitle.contains(where: { title.contains($0) }) { score -= 5 }
            // "Re Edited" / re-uploaded cuts are not the original video
            if ["re edited", "re-edited", "reedited", "re edit", "re-edit", "reedit"].contains(where: { title.contains($0) }) { score -= 5 }
            // "feat. Sumedha Karmahe" is another singer's version of the song, unless the track itself says feat.
            if let featRange = title.range(of: #"\b(feat\.?|ft\.?|featuring)\s+([^|()\[\]\-]+)"#, options: .regularExpression),
               !(songTitle ?? "").lowercased().contains("feat"), !q.contains("feat") {
                let featured = title[featRange].split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !["feat", "featuring"].contains($0) }
                let known = ((artist ?? "") + " " + (songTitle ?? "")).lowercased()
                if !featured.isEmpty && !featured.contains(where: { known.contains($0) }) { score -= 4 }
            }
            if ["new version", "female version", "male version", "unplugged"].contains(where: { title.contains($0) && !q.contains($0) }) { score -= 3 }
            if officialLyricByArtist { score -= 1 } // a real music video, if there is one, still wins
            // Upload from the artist's own channel is the strongest sign of the real thing
            if isArtistChannel { score += 3 }
            // Titles that never say "video" (or official / music) are usually audio over a still image
            let sayVideo = ["video", "official", "music", " mv"].contains(where: { title.contains($0) })
            if !sayVideo && !isArtistChannel && !q.contains("audio") { score -= 3 }
            if title.contains("video song") || title.contains("full video") { score += 2 }
            // A proper video from a label beats an "Audio Song" upload for the same song
            if title.contains("audio song") && !title.contains("video") && !q.contains("audio") { score -= 3 }
            if officialTitle.contains(where: { title.contains($0) }) && officialChannels.contains(where: { channel.contains($0) }) { score += 2 }
            // Sequels / variants ("Darmiyan 2", "Part 3") are different songs unless the user asked for them
            if title.range(of: #"(?<![\d.])\b[2-9]\b(?![\d.])"#, options: .regularExpression) != nil,
               q.range(of: #"\b[2-9]\b"#, options: .regularExpression) == nil { score -= 5 }
            if ["female version", "reprise", "unplugged", "mashup", "flute", "piano"].contains(where: { title.contains($0) && !q.contains($0) }) { score -= 4 }
            // "Pilla Full Song" (no "video") is usually the audio over a still poster
            // (YRF, T-Series, Zee, Tips and VEVO title their real music videos "Full Song")
            let fullSongVideoLabels = ["yrf", "yash raj", "t-series", "zee music", "tips", "vevo", "sony music india"]
            if title.contains("full song") && !title.contains("video") && !q.contains("audio")
                && !fullSongVideoLabels.contains(where: { channel.contains($0) }) { score -= 2 }
            if let movie, !movieWords.isEmpty {
                let movieMatched = movieWords.filter { titleKey.contains(translit($0)) }.count
                if movieMatched == movieWords.count { score += 3 } else if movieMatched > 0 { score += 1 }
            }
            
            // Known track: its song name must be in the video title
            if !songWords.isEmpty {
                // The whole song name, or at least 3/4 of its real words, must be in the title
                let songMatched = significantSongWords.filter { titleKey.contains(translit($0)) }.count
                let fullNameMatch = titleKey.contains(songKey)
                if !fullNameMatch && Double(songMatched) / Double(significantSongWords.count) < 0.75 { continue }
                // A title segment that starts with the song name: "Ishq Movie || Chinnadana Neekosam Video Song"
                // beats "Vayyari Chepakalla Chinnadhana | Full Video Song"
                let segments = title.split(whereSeparator: { "|(-:".contains($0) })
                if segments.contains(where: { translit(String($0)).hasPrefix(songKey) }) { score += 2 }
            }
            if let expected = expectedDuration, expected > 0, r.duration > 0 {
                let diff = abs(r.duration - expected)
                if diff <= 15 { score += 3 } else if diff <= 40 { score += 1 } else if diff > 90 { score -= 2 }
            }
            
            if officialTitle.contains(where: { title.contains($0) }) { score += 3 }
            if officialChannels.contains(where: { channel.contains($0) }) { score += 4 }
            // Artist's own channel, e.g. "The Weeknd" uploading "The Weeknd - Blinding Lights"
            if channel.count > 2 && title.hasPrefix(channel) { score += 2 }
            if penalized.contains(where: { title.contains($0) && !q.contains($0) }) { score -= 3 }
            
            if !artistNames.isEmpty {
                let channelKey = translit(channel)
                // Only the first credited artist counts in the title: later names are often the film's
                // actor ("Pawan Kalyan"), who appears in every song of the movie
                let artistMatched = artistNames.first.map { name in
                    name.allSatisfy { titleKey.contains(translit($0)) || channelKey.contains(translit($0)) }
                } ?? false
                if artistMatched {
                    score += 3
                } else if let dash = title.range(of: " - "), translit(String(title[..<dash.lowerBound])).count >= 3 {
                    // "Beth - Don't You Worry Child": credited to someone else, usually a cover
                    score -= 3
                }
            }
            if let language, let videoLang = Self.videoLanguage(title: r.title, channel: r.channel) {
                // Prefer the version in the wanted language; push other languages down
                if videoLang == language { score += 4 } else if !q.contains(videoLang) { score -= 4 }
            }
            
            score -= Double(index) * 0.15 // keep YouTube's own order as a tiebreaker
            scored.append((r, score))
        }
        
        // Anything scoring this low is a loose match (talks, events, other songs): better to find nothing
        let ranked = scored.sorted { $0.score > $1.score }.filter { $0.score >= 6 }
        AppLog.log("search", "ranked \"\(query)\" song=\(songTitle ?? "-") movie=\(movie ?? "-") expected=\(Int(expectedDuration ?? 0))s: \(results.count) results, \(ranked.count) kept")
        for (i, item) in ranked.prefix(5).enumerated() {
            AppLog.log("search", "  #\(i + 1) score=\(String(format: "%.1f", item.score)) \(item.result.id) \(Int(item.result.duration))s [\(item.result.channel)] \(item.result.title)")
        }
        return ranked.map(\.result)
    }
}
