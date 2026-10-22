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
        "\\|.*$"
    ]
    
    public static func clean(title: String, artist: String) -> CleanedMetadata {
        var cleanTitle = title
        
        // Remove junk patterns
        for pattern in junkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: cleanTitle.utf16.count)
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, options: [], range: range, withTemplate: "")
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
        
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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
