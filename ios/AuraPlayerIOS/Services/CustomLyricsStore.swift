import Foundation

/// Lyrics you wrote or fixed yourself. Kept per song (all copies of a song share them) and used
/// instead of the lyrics found online.
@MainActor
public final class CustomLyricsStore {
    public static let shared = CustomLyricsStore()
    
    public struct Entry: Codable, Equatable {
        public var lines: [String]
        /// Seconds into the song each line starts; nil for a line not synced yet
        public var times: [Double?]
        /// When it was last edited (seconds since 1970): the newer copy wins when two devices changed the same song
        public var modified: Double?
        
        public init(lines: [String], times: [Double?], modified: Double? = nil) {
            self.lines = lines; self.times = times; self.modified = modified
        }
        
        func sameContent(_ other: Entry) -> Bool { lines == other.lines && times == other.times }
        
        public var isFullySynced: Bool { !lines.isEmpty && times.count == lines.count && !times.contains(where: { $0 == nil }) }

        /// A time for every line, so a few lines that were never tapped don't turn highlighting off:
        /// they get a time between their neighbours. If timestamps are missing, provides a natural progression.
        var filledTimes: [Double]? {
            guard !lines.isEmpty else { return nil }
            let known = times.enumerated().compactMap { i, t in t.map { (i, $0) } }
            if known.count >= 2 {
                var out = [Double](repeating: 0, count: lines.count)
                for (i, t) in known { out[i] = t }
                for i in 0..<lines.count where i >= times.count || times[i] == nil {
                    let before = known.last { $0.0 < i }
                    let after = known.first { $0.0 > i }
                    switch (before, after) {
                    case let (b?, a?): out[i] = b.1 + (a.1 - b.1) * Double(i - b.0) / Double(a.0 - b.0)
                    case let (b?, nil): out[i] = b.1 + 4.5 * Double(i - b.0)
                    case let (nil, a?): out[i] = max(0, a.1 - 4.5 * Double(a.0 - i))
                    default: break
                    }
                }
                return out
            }
            if known.count == 1 {
                let (idx, t) = known[0]
                return (0..<lines.count).map { i in max(0, t + Double(i - idx) * 5.0) }
            }
            // Natural default distribution: 15s intro, 5.0s per line
            return (0..<lines.count).map { i in 15.0 + Double(i) * 5.0 }
        }
    }
    
    private var entries: [String: Entry] = [:]
    private let url: URL
    
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("custom_lyrics.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else if let bundleURL = Bundle.main.url(forResource: "custom_lyrics", withExtension: "json"),
                  let data = try? Data(contentsOf: bundleURL),
                  let bundled = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = bundled
            try? data.write(to: url)
        }
    }
    
    /// Same song under different video titles / singer spellings shares one key
    static func key(for track: MediaTrack) -> String {
        "\(ArtistPhotoService.normalize(track.coreTitle))|\(ArtistPhotoService.normalize(ArtistPhotoService.firstArtist(of: track.artist)))"
    }
    
    public func entry(for track: MediaTrack) -> Entry? { entries[Self.key(for: track)] }
    
    public func hasLyrics(for track: MediaTrack) -> Bool { entries[Self.key(for: track)] != nil }
    
    public func save(_ entry: Entry, for track: MediaTrack) {
        var entry = entry
        entry.modified = Date().timeIntervalSince1970
        entries[Self.key(for: track)] = entry
        persist()
    }
    
    /// Every song's lyrics, for syncing
    public var all: [String: Entry] { entries }
    
    /// Used after a sync
    public func replaceAll(_ merged: [String: Entry]) {
        entries = merged
        persist()
    }
    
    public func remove(for track: MediaTrack) {
        entries[Self.key(for: track)] = nil
        persist()
    }
    
    /// As the player shows them: synced when every line has a time, otherwise plain text
    public func lyrics(for track: MediaTrack) -> SongLyrics? {
        guard let entry = entry(for: track), !entry.lines.isEmpty else { return nil }
        if let times = entry.filledTimes {
            let lines = zip(entry.lines, times).map { LyricLine(time: $1, text: $0) }.sorted { $0.time < $1.time }
            return SongLyrics(plainLyrics: entry.lines.joined(separator: "\n"), syncedLines: lines)
        }
        return SongLyrics(plainLyrics: entry.lines.joined(separator: "\n"), syncedLines: [])
    }
    
    private func persist() {
        let snapshot = entries
        let url = url
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
    
    // MARK: - Reading text
    
    /// Splits pasted text into lines. Text in LRC format ("[01:23.45] words") comes with its times.
    nonisolated public static func parse(_ text: String) -> Entry {
        let rawLines = text.components(separatedBy: .newlines)
        let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
        
        var lines: [String] = []
        var times: [Double?] = []
        var tagged = 0
        var plainCount = 0
        for raw in rawLines {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            let stripped = tag.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            if matches.isEmpty {
                // [ar:Artist] style info lines aren't lyrics
                if raw.range(of: #"^\s*\[[a-z]{2,}:.*\]\s*$"#, options: .regularExpression) != nil { continue }
                let t = raw.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                lines.append(t); times.append(nil); plainCount += 1
            } else if !stripped.isEmpty {
                // a line can carry several times when it repeats: "[00:10][01:30] chorus"
                for m in matches {
                    let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                    let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                    lines.append(stripped); times.append(min * 60 + sec); tagged += 1
                }
            }
        }
        // Mostly timed lines: it's an LRC file. Keep it in time order.
        if tagged > 0 && tagged >= plainCount {
            let paired = zip(lines, times).sorted { ($0.1 ?? .infinity) < ($1.1 ?? .infinity) }
            return Entry(lines: paired.map(\.0), times: paired.map(\.1))
        }
        // Otherwise it's plain text: forget any stray tags
        return Entry(lines: lines, times: Array(repeating: nil, count: lines.count))
    }
}
