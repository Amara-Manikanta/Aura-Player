import Foundation

/// Lyrics written or synced by hand, here or on the iPhone (iPhone Sync keeps both in step): used instead of the online ones.
/// Saved per song in custom_lyrics.json, in the same format the iPhone app uses.
enum CustomLyricsFile {
    struct Entry: Codable, Equatable {
        var lines: [String]
        /// Seconds into the song each line starts; nil for a line not synced yet
        var times: [Double?]
        /// When it was last edited (seconds since 1970): the newer copy wins when two devices changed the same song
        var modified: Double?
        
        var isFullySynced: Bool { !lines.isEmpty && times.count == lines.count && !times.contains(where: { $0 == nil }) }

        /// A time for every line, so a few lines that were never tapped don't turn highlighting off:
        /// they get a time between their neighbours. nil when too few lines are synced to follow along.
        var filledTimes: [Double]? {
            guard times.count == lines.count else { return nil }
            let known = times.enumerated().compactMap { i, t in t.map { (i, $0) } }
            guard known.count >= 2, known.count * 2 >= lines.count else { return nil }
            var out = [Double](repeating: 0, count: lines.count)
            for (i, t) in known { out[i] = t }
            for i in 0..<lines.count where times[i] == nil {
                let before = known.last { $0.0 < i }
                let after = known.first { $0.0 > i }
                switch (before, after) {
                case let (b?, a?): out[i] = b.1 + (a.1 - b.1) * Double(i - b.0) / Double(a.0 - b.0)
                case let (b?, nil): out[i] = b.1 + 4 * Double(i - b.0)
                case let (nil, a?): out[i] = max(0, a.1 - 4 * Double(a.0 - i))
                default: break
                }
            }
            return out
        }
    }
    
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AuraPlayer/custom_lyrics.json")
    }
    
    /// Same song under different video titles / singer spellings shares one key
    static func key(title: String, artist: String) -> String {
        let song = MediaTrack(title: title, artist: artist, sourceType: .youtube, originalURL: "")
        return "\(ArtistPhotoService.normalize(song.coreTitle))|\(ArtistPhotoService.normalize(ArtistPhotoService.firstArtist(of: artist)))"
    }
    
    private static func loadAll() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url), let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all
    }
    
    static func entry(title: String, artist: String) -> Entry? {
        loadAll()[key(title: title, artist: artist)]
    }
    
    static func save(_ entry: Entry, title: String, artist: String) {
        var all = loadAll()
        var entry = entry
        entry.modified = Date().timeIntervalSince1970
        all[key(title: title, artist: artist)] = entry
        write(all)
    }
    
    static func remove(title: String, artist: String) {
        var all = loadAll()
        all[key(title: title, artist: artist)] = nil
        write(all)
    }
    
    private static func write(_ all: [String: Entry]) {
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }
    
    /// As the player shows them: synced when every line has a time, otherwise plain text
    static func lyrics(title: String, artist: String) -> SongLyrics? {
        guard let entry = entry(title: title, artist: artist), !entry.lines.isEmpty else { return nil }
        let plain = entry.lines.joined(separator: "\n")
        if let times = entry.filledTimes {
            let lines = zip(entry.lines, times).map { LyricLine(time: $1, text: $0) }.sorted { $0.time < $1.time }
            return SongLyrics(plainLyrics: plain, syncedLines: lines)
        }
        return SongLyrics(plainLyrics: plain, syncedLines: [])
    }
    
    // MARK: - Reading pasted text
    
    /// Splits pasted text into lines. Text in LRC format ("[01:23.45] words") comes with its times.
    static func parse(_ text: String) -> Entry {
        let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
        var lines: [String] = []
        var times: [Double?] = []
        var tagged = 0, plainCount = 0
        for raw in text.components(separatedBy: .newlines) {
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
        if tagged > 0 && tagged >= plainCount {
            let paired = zip(lines, times).sorted { ($0.1 ?? .infinity) < ($1.1 ?? .infinity) }
            return Entry(lines: paired.map(\.0), times: paired.map(\.1), modified: nil)
        }
        return Entry(lines: lines, times: Array(repeating: nil, count: lines.count), modified: nil)
    }
}
