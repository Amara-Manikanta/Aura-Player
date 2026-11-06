import Foundation

extension YouTubeService {
    /// Plain YouTube search: whatever YouTube lists for the words (videos of every kind, not just songs).
    /// Read from the public results page, so it doesn't need yt-dlp.
    public func directSearch(query: String) async -> [YouTubeSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        if let id = extractVideoId(from: clean) {
            return [YouTubeSearchResult(
                id: id, title: "YouTube Video", channel: "YouTube", duration: 0,
                thumbnailURL: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                url: "https://www.youtube.com/watch?v=\(id)")]
        }
        
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return [] }
        return Self.parseVideos(html: html, channel: "YouTube", limit: 25)
    }
}
