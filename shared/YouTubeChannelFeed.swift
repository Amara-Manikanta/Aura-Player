import Foundation

/// A YouTube channel the user follows, shown on the YouTube search page
public struct FavoriteChannel: Identifiable, Hashable, Sendable {
    public let name: String
    public let handle: String      // without the "@"
    public let topic: String
    public var id: String { handle }
    
    public init(_ name: String, _ handle: String, _ topic: String) {
        self.name = name; self.handle = handle; self.topic = topic
    }
}

public enum FavoriteChannels {
    public static let topics = ["Tech", "AI & Code", "Music", "Movies", "Science", "More"]
    
    public static let all: [FavoriteChannel] = [
        // Tech & Gadgets
        .init("Marques Brownlee", "mkbhd", "Tech"),
        .init("Apple", "Apple", "Tech"),
        .init("JerryRigEverything", "JerryRigEverything", "Tech"),
        .init("Samsung", "Samsung", "Tech"),
        .init("MacRumors", "macrumors", "Tech"),
        .init("Linus Tech Tips", "LinusTechTips", "Tech"),
        .init("Mrwhosetheboss", "Mrwhosetheboss", "Tech"),
        .init("Unbox Therapy", "unboxtherapy", "Tech"),
        .init("Proper Honest Tech", "ProperHonestTech", "Tech"),
        .init("Stephen Robles", "beardfm", "Tech"),
        .init("DJI", "DJI", "Tech"),
        .init("Insta360", "insta360", "Tech"),
        .init("Sony | Camera", "ImagingbySony", "Tech"),
        .init("CarryPro", "carrypro_official", "Tech"),
        .init("Brandon Butch", "BrandonButch", "Tech"),
        // AI & Coding
        .init("Claude", "claude", "AI & Code"),
        .init("IBM Technology", "IBMTechnology", "AI & Code"),
        .init("Krish Naik", "krishnaik06", "AI & Code"),
        .init("Telusko", "Telusko", "AI & Code"),
        .init("Programming with Mosh", "programmingwithmosh", "AI & Code"),
        .init("GeeksforGeeks", "GeeksforGeeksVideos", "AI & Code"),
        .init("John Savill's Technical Training", "NTFAQGuy", "AI & Code"),
        // Music
        .init("T-Series", "tseries", "Music"),
        .init("Sony Music India", "SonyMusicIndia", "Music"),
        .init("YRF", "yrf", "Music"),
        .init("Anirudh Ravichander", "AnirudhOfficial", "Music"),
        .init("Ed Sheeran", "EdSheeran", "Music"),
        .init("Taylor Swift", "TaylorSwift", "Music"),
        .init("Katy Perry", "KatyPerry", "Music"),
        .init("Selena Gomez", "selenagomez", "Music"),
        .init("Enrique Iglesias", "EnriqueIglesias", "Music"),
        .init("Alan Walker", "Alanwalkermusic", "Music"),
        .init("New Rockstars", "NewRockstars", "Music"),
        .init("Behind The Music", "behindthemusic1959", "Music"),
        .init("Aakanksha Monga", "aakanksha_monga", "Music"),
        .init("SruthiRocks", "SruthiRocks", "Music"),
        .init("Kavyashree Vissamsetti", "sarvaaniarts", "Music"),
        // Movies & Shows
        .init("Marvel Entertainment", "marvel", "Movies"),
        .init("Warner Bros.", "WarnerBros", "Movies"),
        .init("20th Century Studios India", "20thCenturyStudiosIndia", "Movies"),
        .init("Avatar", "AvatarOfficial", "Movies"),
        .init("Aevy TV", "aevytv", "Movies"),
        // Science & Space
        .init("ISRO", "isroofficial5866", "Science"),
        .init("NASA", "NASA", "Science"),
        .init("National Geographic", "NatGeo", "Science"),
        .init("Discovery", "discovery", "Science"),
        .init("Guinness World Records", "guinnessworldrecords", "Science"),
        // Learning & More
        .init("Think School", "ThinkSchool", "More"),
        .init("PiXimperfect", "PiXimperfect", "More"),
        .init("The Wall Street Journal", "wsj", "More"),
        .init("Kara and Nate", "KaraandNate", "More"),
    ]
}

extension YouTubeService {
    /// The latest videos of a channel, read from its public Videos page (the same kind of page the search reads)
    public func channelVideos(handle: String, name: String? = nil, limit: Int = 30) async -> [YouTubeSearchResult] {
        guard let url = URL(string: "https://www.youtube.com/@\(handle)/videos") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return [] }
        
        return Self.parseVideos(html: html, channel: name ?? handle, limit: limit)
    }
    
    /// Videos listed in a YouTube page (a search, or a channel's Videos tab), read from the page's own data
    static func parseVideos(html: String, channel: String, limit: Int) -> [YouTubeSearchResult] {
        let marker = "var ytInitialData = "
        guard let start = html.range(of: marker)?.upperBound,
              let end = html[start...].range(of: ";</script>")?.lowerBound,
              let json = try? JSONSerialization.jsonObject(with: Data(html[start..<end].utf8)) else { return [] }
        var found: [YouTubeSearchResult] = []
        var seen = Set<String>()
        collectVideos(in: json, channel: channel, into: &found, seen: &seen, limit: limit)
        return found
    }
    
    private static func collectVideos(in node: Any, channel: String, into out: inout [YouTubeSearchResult], seen: inout Set<String>, limit: Int) {
        guard out.count < limit else { return }
        if let dict = node as? [String: Any] {
            // Current layout: "lockup" items; older layout: videoRenderer
            if let lockup = dict["lockupViewModel"] as? [String: Any],
               lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
               let id = lockup["contentId"] as? String, seen.insert(id).inserted {
                let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
                let title = ((metadata?["title"] as? [String: Any])?["content"] as? String) ?? "Video"
                out.append(YouTubeSearchResult(
                    id: id, title: title, channel: channel,
                    duration: durationText(in: lockup["contentImage"]),
                    thumbnailURL: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                    url: "https://www.youtube.com/watch?v=\(id)"))
                return
            }
            if let v = dict["videoRenderer"] as? [String: Any], let id = v["videoId"] as? String, seen.insert(id).inserted {
                let runs = (v["title"] as? [String: Any])?["runs"] as? [[String: Any]]
                let title = (runs?.first?["text"] as? String) ?? "Video"
                let owner = ((v["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String
                let length = ((v["lengthText"] as? [String: Any])?["simpleText"] as? String) ?? ""
                out.append(YouTubeSearchResult(
                    id: id, title: title, channel: owner ?? channel, duration: seconds(from: length),
                    thumbnailURL: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                    url: "https://www.youtube.com/watch?v=\(id)"))
                return
            }
            for value in dict.values { collectVideos(in: value, channel: channel, into: &out, seen: &seen, limit: limit) }
        } else if let array = node as? [Any] {
            for value in array { collectVideos(in: value, channel: channel, into: &out, seen: &seen, limit: limit) }
        }
    }
    
    /// "12:34" in the thumbnail's length badge
    private static func durationText(in node: Any?) -> TimeInterval {
        guard let node else { return 0 }
        if let dict = node as? [String: Any] {
            if let badge = dict["thumbnailBadgeViewModel"] as? [String: Any], let text = badge["text"] as? String {
                return seconds(from: text)
            }
            for value in dict.values {
                let t = durationText(in: value)
                if t > 0 { return t }
            }
        } else if let array = node as? [Any] {
            for value in array {
                let t = durationText(in: value)
                if t > 0 { return t }
            }
        }
        return 0
    }
    
    private static func seconds(from text: String) -> TimeInterval {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2, parts.count <= 3 else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
