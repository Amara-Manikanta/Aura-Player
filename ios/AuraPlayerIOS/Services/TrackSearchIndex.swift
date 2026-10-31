import Foundation

/// Fast "search in playlist": each song's searchable text (and its spelling-folded form) is worked out once
/// and remembered, so typing only does cheap substring checks. (Finding the movie name needs a regex and the
/// folding needs a dozen string replacements; doing that for every song on every keystroke made typing lag.)
@MainActor
enum TrackSearchIndex {
    private struct Entry {
        let title: String, artist: String, album: String?
        let plain: String
        let loose: String
    }
    private static var cache: [UUID: Entry] = [:]
    
    /// Songs where every typed word matches the title, singer, album or movie; spelling variants count
    /// ("Chinnadana" finds "Chinnadhana")
    static func filter(_ tracks: [MediaTrack], query: String) -> [MediaTrack] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return tracks }
        let looseWords = words.map { YouTubeService.translit($0) }
        return tracks.filter { track in
            let entry = entry(for: track)
            for (word, loose) in zip(words, looseWords) {
                if !entry.plain.contains(word) && !entry.loose.contains(loose) { return false }
            }
            return true
        }
    }
    
    private static func entry(for t: MediaTrack) -> Entry {
        if let cached = cache[t.id], cached.title == t.title, cached.artist == t.artist, cached.album == t.album {
            return cached
        }
        let text = [t.title, t.artist, t.album ?? "", t.movieName ?? ""].joined(separator: " ")
        let entry = Entry(
            title: t.title, artist: t.artist, album: t.album,
            plain: text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased(),
            loose: YouTubeService.translit(text)
        )
        cache[t.id] = entry
        return entry
    }
}
