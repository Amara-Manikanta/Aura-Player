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
    
    var filter: String {
        switch self {
        case .week: return "CAISAhAB"
        case .month: return "CAISAhAC"
        }
    }
}

public struct NewRelease: Identifiable, Sendable {
    public var id: String { video.id }
    public let video: YouTubeSearchResult
    public let views: Int
    public let uploadedAgo: String
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
    
    public func newReleases(language: String, period: ReleasePeriod) async -> [NewRelease] {
        let lang = language.lowercased()
        let q = lang == "english" ? "new official music video" : "\(lang) new song official video"
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=\(period.filter)") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return [] }
            
            let parsed = parseInitialData(from: html)
            let items = parsed.isEmpty ? parseFallbackRegex(from: html) : parsed
            return items.map {
                NewRelease(video: $0, views: 0, uploadedAgo: period.rawValue)
            }
        } catch {
            return []
        }
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
    
    private func parseInitialData(from html: String) -> [YouTubeSearchResult] {
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
        
        var results: [YouTubeSearchResult] = []
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
                
                results.append(
                    YouTubeSearchResult(
                        id: vid,
                        title: titleText,
                        channel: channelText,
                        duration: durationSec,
                        thumbnailURL: thumbURL,
                        url: "https://www.youtube.com/watch?v=\(vid)"
                    )
                )
                
                if results.count >= 25 { break }
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
