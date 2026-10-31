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

public enum ReleasePeriod: String, CaseIterable, Sendable {
    case week = "This Week"
    case month = "This Month"
    
    /// YouTube search filter: uploaded this week / this month, videos only (same as the Mac app)
    var filter: String { self == .week ? "EgQIAxAB" : "EgQIBBAB" }
}

public struct NewRelease: Identifiable, Hashable, Sendable {
    public var id: String { video.id }
    public let video: YouTubeSearchResult
    public let views: Int
    /// "3 days ago" as YouTube shows it
    public let uploadedAgo: String
}

/// One song of a YouTube "Mix"
public struct MixEntry: Sendable {
    public let id: String
    public let title: String
    public let channel: String
    public let duration: Double
}

public actor YouTubeService {
    public static let shared = YouTubeService()
    
    private var videoIdCache: [String: String] = [:]
    
    private init() {}
    
    public func extractVideoId(from urlOrId: String) -> String? {
        let trimmed = urlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains("?") && !trimmed.contains(" ") {
            return trimmed
        }
        
        if let url = URL(string: trimmed), let host = url.host?.lowercased() {
            if host.contains("youtu.be") {
                return url.pathComponents.dropFirst().first
            } else if host.contains("youtube.com") {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems {
                    for item in queryItems where item.name == "v" {
                        return item.value
                    }
                }
                if url.path.contains("/shorts/") || url.path.contains("/embed/") {
                    return url.pathComponents.last
                }
            }
        }
        return nil
    }
    
    private var newReleaseCache: [String: (date: Date, items: [NewRelease])] = [:]
    
    /// Songs uploaded recently in a language, official labels and real videos first (Mac app's rules).
    public func newReleases(language: String, period: ReleasePeriod, forceRefresh: Bool = false) async -> [NewRelease] {
        let cacheKey = "\(language)|\(period.rawValue)"
        if !forceRefresh, let cached = newReleaseCache[cacheKey], Date().timeIntervalSince(cached.date) < 1800 {
            return cached.items
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
            guard let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=\(period.filter)\(region)"),
                  let html = await fetchHTML(url) else { continue }
            for item in parseVideoItems(from: html, limit: 40) where seen.insert(item.video.id).inserted {
                guard Self.looksLikeNewSong(item.video, language: lang) else { continue }
                items.append(NewRelease(video: item.video, views: item.views, uploadedAgo: item.published))
            }
        }
        let ranked = items.sorted { Self.releaseScore($0) > Self.releaseScore($1) }
        if !ranked.isEmpty { newReleaseCache[cacheKey] = (Date(), ranked) }
        Self.log("releases", "\(language) \(period.rawValue): \(ranked.count) songs")
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
    
    // MARK: - YouTube Mix
    
    /// YouTube's "Mix" for a song (list=RD<id>): what millions of listeners play together with it.
    /// Uses YouTube's own web API, the same request the website makes (no sign-in needed).
    public func fetchMix(videoId: String) async -> [MixEntry] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20241010.00.00", "hl": "en", "gl": "IN"]],
            "videoId": videoId,
            "playlistId": "RD\(videoId)"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = root["contents"] as? [String: Any],
              let watch = contents["twoColumnWatchNextResults"] as? [String: Any],
              let playlistOuter = watch["playlist"] as? [String: Any],
              let playlist = playlistOuter["playlist"] as? [String: Any],
              let items = playlist["contents"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let r = item["playlistPanelVideoRenderer"] as? [String: Any],
                  let id = r["videoId"] as? String else { return nil }
            let title = Self.text(r["title"]) ?? ""
            guard !title.isEmpty else { return nil }
            let channel = Self.text(r["shortBylineText"]) ?? "YouTube"
            let duration = (Self.text(r["lengthText"])).map(parseDurationText) ?? 0
            return MixEntry(id: id, title: title, channel: channel, duration: duration)
        }
    }
    
    /// Text from YouTube's {simpleText} or {runs:[{text}]} objects
    static func text(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }
    
    private func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Real title, channel and length for a pasted link (the search page only knows the video id)
    public func linkDetails(videoId: String) async -> YouTubeSearchResult? {
        guard let oembed = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json") else { return nil }
        var request = URLRequest(url: oembed)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else { return nil }
        let channel = (json["author_name"] as? String) ?? "YouTube"
        // Only the watch page has the length
        var seconds: TimeInterval = 0
        if let page = URL(string: "https://www.youtube.com/watch?v=\(videoId)"), let html = await fetchHTML(page),
           let r = html.range(of: #""lengthSeconds":"(\d+)""#, options: .regularExpression) {
            seconds = TimeInterval(html[r].filter(\.isNumber)) ?? 0
        }
        return YouTubeSearchResult(
            id: videoId, title: title, channel: channel, duration: seconds,
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            url: "https://www.youtube.com/watch?v=\(videoId)"
        )
    }
    
    /// Fetches live search suggestions as the user types
    public func getSuggestions(query: String) async -> [String] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=\(encoded)") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  jsonArray.count >= 2,
                  let suggestions = jsonArray[1] as? [String] else { return [] }
            return suggestions
        } catch {
            return []
        }
    }
    
    /// Searches YouTube and returns structured results
    public func search(query: String) async -> [YouTubeSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        if let directId = extractVideoId(from: clean) {
            let directResult = YouTubeSearchResult(
                id: directId,
                title: "YouTube Video",
                channel: "YouTube",
                duration: 0,
                thumbnailURL: "https://i.ytimg.com/vi/\(directId)/hqdefault.jpg",
                url: "https://www.youtube.com/watch?v=\(directId)"
            )
            return [directResult]
        }
        
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return []
        }
        
        do {
            var request = URLRequest(url: searchURL)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return [] }
            
            // Method 1: Parse structured ytInitialData
            let parsed = parseInitialData(from: html)
            if !parsed.isEmpty {
                return parsed
            }
            
            // Method 2: Fallback regex
            return parseFallbackRegex(from: html)
        } catch {
            return []
        }
    }
    
    /// Resolves an optimal official videoId for a given track
    public func resolveVideoId(for queryOrTitle: String, artist: String = "") async -> String? {
        let cacheKey = "\(queryOrTitle.lowercased())|\(artist.lowercased())"
        if let cached = videoIdCache[cacheKey] {
            return cached
        }
        
        // Direct YouTube URL or 11-char ID
        if queryOrTitle.count == 11 && !queryOrTitle.contains(" ") {
            return queryOrTitle
        }
        if let url = URL(string: queryOrTitle), let host = url.host?.lowercased() {
            if host.contains("youtube.com"), let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                if let v = queryItems.first(where: { $0.name == "v" })?.value {
                    return v
                }
            } else if host.contains("youtu.be") {
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !path.isEmpty { return path }
            }
        }
        
        var query = "\(queryOrTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = query.lowercased()
        if !lower.contains("official") && !lower.contains("video") {
            query += " official music video"
        }
        
        let results = await search(query: query)
        if let first = results.first {
            videoIdCache[cacheKey] = first.id
            return first.id
        }
        
        return nil
    }
    

    // MARK: - Official video search (same ranking as the Mac app)
    
    static func log(_ category: String, _ message: String) {
        #if DEBUG
        print("[\(category)] \(message)")
        #endif
    }
    
    /// YouTube search ranked so the official video song comes first (lyric videos, Shorts, covers,
    /// re-uploads, other languages… pushed down or removed). Same rules as the Mac app.
    public func searchVideos(query: String, limit: Int = 8, songTitle: String? = nil, artist: String? = nil,
                             movie: String? = nil, expectedDuration: TimeInterval? = nil, language: String? = nil) async throws -> [YouTubeSearchResult] {
        if let direct = extractVideoId(from: query) {
            return await search(query: direct)
        }
        let raw = await search(query: Self.officialSearchQuery(for: query))
        return Array(Self.rankOfficialVideos(raw, query: query, songTitle: songTitle, artist: artist, movie: movie,
                                             expectedDuration: expectedDuration, language: language).prefix(limit))
    }
    
    /// Best official video for a saved song (uses its title, artist, movie, length and language).
    public func resolveVideo(for track: MediaTrack, language: String?, excluding: Set<String> = []) async -> String? {
        let addedByLink = track.originalURL.lowercased().hasPrefix("http")
        if addedByLink, excluding.isEmpty, let id = extractVideoId(from: track.originalURL) { return id }
        let query = track.videoSearchQuery
        let cacheKey = "\(query.lowercased())|\(language ?? "")"
        if excluding.isEmpty, let cached = videoIdCache[cacheKey] { return cached }
        
        // After a 👎 / blocked video, try a few phrasings of the same song before giving up
        let core = Self.coreSongTitle(track.title)
        let mainArtist = track.artist.components(separatedBy: CharacterSet(charactersIn: "&,(")).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var variants = [query]
        if !excluding.isEmpty {
            if let movie = track.movieName { variants.append("\(core) \(movie) full video song") }
            if !mainArtist.isEmpty { variants.append("\(core) \(mainArtist) official video") }
        }
        for variant in variants {
            let ranked = (try? await languageAwareSearch(
                query: variant, limit: 12, songTitle: addedByLink ? nil : track.title, artist: track.artist,
                movie: track.movieName, expectedDuration: track.duration > 0 ? track.duration : nil, language: language)) ?? []
            if let best = ranked.first(where: { !excluding.contains($0.id) }) {
                Self.log("resolve", "picked \(best.id) for \"\(variant)\" language=\(language ?? "-"): \(best.title)")
                videoIdCache[cacheKey] = best.id
                return best.id
            }
        }
        Self.log("resolve", "nothing for \"\(query)\" (excluded \(excluding.count))")
        return nil
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
            Self.log("search", "using \(language) version for \"\(query)\": \(top.title)")
            return dubbed
        }
        Self.log("search", "no \(language) version for \"\(query)\", using original")
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
        Self.log("search", "ranked \"\(query)\" song=\(songTitle ?? "-") movie=\(movie ?? "-") expected=\(Int(expectedDuration ?? 0))s: \(results.count) results, \(ranked.count) kept")
        for (i, item) in ranked.prefix(5).enumerated() {
            Self.log("search", "  #\(i + 1) score=\(String(format: "%.1f", item.score)) \(item.result.id) \(Int(item.result.duration))s [\(item.result.channel)] \(item.result.title)")
        }
        return ranked.map(\.result)
    }

    private func parseInitialData(from html: String) -> [YouTubeSearchResult] {
        parseVideoItems(from: html, limit: 25).map(\.video)
    }
    
    /// Search results with their view counts and upload age ("3 days ago")
    private func parseVideoItems(from html: String, limit: Int) -> [(video: YouTubeSearchResult, views: Int, published: String)] {
        let marker = "var ytInitialData = "
        guard let markerRange = html.range(of: marker) else { return [] }
        let jsonStart = markerRange.upperBound
        guard let scriptEndRange = html[jsonStart...].range(of: ";</script>") else { return [] }
        let jsonString = String(html[jsonStart..<scriptEndRange.lowerBound])
        
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = root["contents"] as? [String: Any],
              let twoCol = contents["twoColumnSearchResultsRenderer"] as? [String: Any],
              let primary = twoCol["primaryContents"] as? [String: Any],
              let sectionList = primary["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]] else {
            return []
        }
        
        var results: [(video: YouTubeSearchResult, views: Int, published: String)] = []
        var seenIds = Set<String>()
        
        for section in sectionContents {
            guard let itemSection = section["itemSectionRenderer"] as? [String: Any],
                  let items = itemSection["contents"] as? [[String: Any]] else { continue }
            
            for item in items {
                guard let v = item["videoRenderer"] as? [String: Any],
                      let vid = v["videoId"] as? String,
                      seenIds.insert(vid).inserted else { continue }
                
                // Title
                var titleText = "Unknown Title"
                if let titleDict = v["title"] as? [String: Any],
                   let runs = titleDict["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let t = firstRun["text"] as? String {
                    titleText = t
                }
                
                // Channel / Owner
                var channelText = "YouTube"
                if let ownerDict = v["ownerText"] as? [String: Any],
                   let runs = ownerDict["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let c = firstRun["text"] as? String {
                    channelText = c
                }
                
                // Duration
                var durationSec: TimeInterval = 0
                if let lengthDict = v["lengthText"] as? [String: Any],
                   let simple = lengthDict["simpleText"] as? String {
                    durationSec = parseDurationText(simple)
                }
                
                // Thumbnail
                var thumbURL: String = "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg"
                if let thumbDict = v["thumbnail"] as? [String: Any],
                   let thumbnails = thumbDict["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last,
                   let u = lastThumb["url"] as? String {
                    thumbURL = u
                }
                
                // "1,234,567 views"
                let viewsText = Self.text(v["viewCountText"]) ?? ""
                let views = Int(viewsText.filter(\.isNumber)) ?? 0
                let published = Self.text(v["publishedTimeText"]) ?? ""
                
                results.append((
                    YouTubeSearchResult(
                        id: vid,
                        title: titleText,
                        channel: channelText,
                        duration: durationSec,
                        thumbnailURL: thumbURL,
                        url: "https://www.youtube.com/watch?v=\(vid)"
                    ),
                    views, published
                ))
                
                if results.count >= limit { break }
            }
        }
        
        return results
    }
    
    private func parseDurationText(_ text: String) -> TimeInterval {
        let parts = text.components(separatedBy: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m * 60 + s
        } else if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
            return h * 3600 + m * 60 + s
        }
        return 0
    }
    
    private func parseFallbackRegex(from html: String) -> [YouTubeSearchResult] {
        var results: [YouTubeSearchResult] = []
        let nsHtml = html as NSString
        let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\".*?\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}\\].*?\"ownerText\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
        var seenIds = Set<String>()
        
        for match in matches where match.numberOfRanges >= 4 {
            let vid = nsHtml.substring(with: match.range(at: 1))
            guard seenIds.insert(vid).inserted else { continue }
            
            let rawTitle = nsHtml.substring(with: match.range(at: 2))
            let channel = nsHtml.substring(with: match.range(at: 3))
            
            let title = rawTitle.replacingOccurrences(of: "\\u0026", with: "&")
                .replacingOccurrences(of: "\\\"", with: "\"")
            
            results.append(
                YouTubeSearchResult(
                    id: vid,
                    title: title,
                    channel: channel,
                    duration: 0,
                    thumbnailURL: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg",
                    url: "https://www.youtube.com/watch?v=\(vid)"
                )
            )
            if results.count >= 20 { break }
        }
        
        return results
    }
}
