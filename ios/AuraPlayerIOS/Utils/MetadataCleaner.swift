import Foundation

public struct CleanedMetadata: Sendable {
    public let cleanTitle: String
    public let primaryArtist: String
}

public enum MetadataCleaner {
    private static let junkPatterns: [String] = [
        "\\(?\\s*official\\s+(music\\s+)?video\\s*\\)?",
        "\\[?\\s*official\\s+(music\\s+)?video\\s*\\]?",
        "\\(?\\s*official\\s+audio\\s*\\)?",
        "\\[?\\s*official\\s+audio\\s*\\]?",
        "\\(?\\s*lyric(s)?\\s*(video)?\\s*\\)?",
        "\\[?\\s*lyric(s)?\\s*(video)?\\s*\\]?",
        "\\(?\\s*visualizer\\s*\\)?",
        "\\[?\\s*visualizer\\s*\\]?",
        "\\(?\\s*4k\\s*(remastered)?\\s*\\)?",
        "\\[?\\s*4k\\s*(remastered)?\\s*\\]?",
        "\\(?\\s*remastered\\s*\\)?",
        "\\[?\\s*remastered\\s*\\]?",
        "\\(?\\s*hd\\s*\\)?",
        "\\[?\\s*hd\\s*\\]?",
        "\\(?\\s*live\\s*\\)?",
        "\\[?\\s*[48]k\\s*\\]?",
        "\\b(full\\s+)?video\\s+songs?\\b",
        "\\bfull\\s+(video|song)\\b",
        "\\bmusic\\s+video\\b",
        "\\b60\\s*fps\\b",
        "\\bsong\\b(?=\\s*(\\(|\\[|$))"   // trailing "Song" in "Naatu Naatu Song (Telugu)"
    ]
    
    /// The part of a YouTube title that names the song. Titles look like
    /// "Naatu Naatu Video Song | RRR | NTR" or "RRR | Naattu Koothu Tamil Video Song | …"
    /// (song first or movie first), so pick the "|" part that says Video Song / Full Video / Song,
    /// and the text after "Movie:" or "Full Video:". (Used to keep only the first part: "RRR".)
    static func songPart(of title: String) -> String {
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "|｜"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        func score(_ p: String) -> Int {
            let l = p.lowercased()
            if l.contains("video song") || l.contains("full video") || l.contains("full song") || l.contains("music video") { return 3 }
            if l.contains("official video") || l.contains(" video") || l.contains("lyric") { return 2 }
            if l.range(of: "\\bsong\\b", options: .regularExpression) != nil { return 1 }
            return 0
        }
        var best = parts.first ?? title
        var bestScore = -1
        for p in parts where score(p) > bestScore { best = p; bestScore = score(p) }
        // "Full Video: Naatu Naatu Song" / "RRR: Naattu Koothu" → after the colon
        if let colon = best.range(of: ":") {
            let before = best[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            let after = best[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            if !after.isEmpty && (before.lowercased().contains("video") || before.split(separator: " ").count <= 3) {
                best = after
            }
        }
        return best
    }
    
    public static func clean(title: String, artist: String) -> CleanedMetadata {
        var cleanTitle = songPart(of: title)
        
        // Remove junk patterns
        for pattern in junkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: cleanTitle.utf16.count)
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, options: [], range: range, withTemplate: " ")  // a space, so words either side stay apart
            }
        }
        
        // If title is "Artist - Song", extract
        if cleanTitle.contains(" - ") {
            let parts = cleanTitle.components(separatedBy: " - ")
            if parts.count >= 2 {
                let possibleArtist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let possibleTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                cleanTitle = possibleTitle
                if artist.isEmpty || artist.contains("- Topic") {
                    return CleanedMetadata(
                        cleanTitle: cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        primaryArtist: cleanPrimaryArtist(possibleArtist)
                    )
                }
            }
        }
        
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\(\\s*\\)|\\[\\s*\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–:,")))
        if cleanTitle.isEmpty { cleanTitle = title }
        return CleanedMetadata(
            cleanTitle: cleanTitle,
            primaryArtist: cleanPrimaryArtist(artist)
        )
    }
    
    private static func cleanPrimaryArtist(_ artist: String) -> String {
        var clean = artist.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
        let separators = [",", "&", "feat.", "ft.", "Feat.", "Ft."]
        for sep in separators {
            if let first = clean.components(separatedBy: sep).first {
                clean = first
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
