import Foundation

/// A singer / composer with every song of theirs in the library (a song sung by two singers counts for both).
public struct ArtistGroup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let trackCount: Int
    public let totalPlayCount: Int
    public let tracks: [MediaTrack]
    public let sampleArtworkURL: String?
}

extension PlaylistStore {
    /// Every artist, songs with several singers listed under each of them (same rules as the Mac app)
    public var allArtists: [ArtistGroup] {
        var tracksByArtist: [String: [MediaTrack]] = [:]
        var spellings: [String: [String: Int]] = [:]   // key → how often each spelling appears

        for track in allUniqueTracks {
            for name in Self.splitArtists(track.artist) {
                let key = ArtistPhotoService.normalize(name)
                guard !key.isEmpty else { continue }
                tracksByArtist[key, default: []].append(track)
                spellings[key, default: [:]][name, default: 0] += 1
            }
        }

        return tracksByArtist.map { key, tracks in
            // "S.P. Balasubrahmanyam" / "S. P. Balasubrahmanyam": show the spelling used most
            let name = spellings[key]?.max { $0.value < $1.value }?.key ?? key
            return ArtistGroup(
                name: name,
                trackCount: tracks.count,
                totalPlayCount: tracks.reduce(0) { $0 + $1.totalPlays },
                tracks: tracks,
                sampleArtworkURL: tracks.compactMap { $0.thumbnailURL }.first
            )
        }
        .sorted { ($0.trackCount, $0.name) > ($1.trackCount, $1.name) }
    }

    /// Names that contain a separator but are one act
    private static let wholeNames = ["Simon & Garfunkel", "Earth, Wind & Fire", "Hall & Oates", "Florence + The Machine",
                                     "Mumford & Sons", "Years & Years", "Of Monsters and Men", "Tom & Jerry",
                                     "Shankar-Ehsaan-Loy", "Vishal-Shekhar", "Vishal & Shekhar", "Salim-Sulaiman", "Salim–Sulaiman",
                                     "Sachin-Jigar", "Jatin-Lalit", "Laxmikant-Pyarelal", "Nadeem-Shravan"]

    /// "Zedd & Katy Perry" → ["Zedd", "Katy Perry"]; "Hari (Live), Chitra feat. X" → ["Hari", "Chitra", "X"]
    public static func splitArtists(_ raw: String) -> [String] {
        var text = raw.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)

        // Shield acts whose names contain "&" or "," so they stay in one piece
        var shielded: [String: String] = [:]
        for (i, whole) in wholeNames.enumerated() where text.range(of: whole, options: .caseInsensitive) != nil {
            let token = "§\(i)§"
            shielded[token] = whole
            text = text.replacingOccurrences(of: whole, with: token, options: .caseInsensitive)
        }

        let parts = text.replacingOccurrences(of: #"(?i)\s+(feat\.?|ft\.?|featuring|with|vs\.?|x)\s+"#, with: ",", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "&,;/+"))

        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            for (token, whole) in shielded { name = name.replacingOccurrences(of: token, with: whole) }
            let key = ArtistPhotoService.normalize(name)
            guard !key.isEmpty, name.lowercased() != "various artists", name != "Unknown Artist", seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }

    /// Playlists that already hold this song (same video, link, or title + artist)
    public func playlists(containing track: MediaTrack) -> [Playlist] {
        playlists.filter { pl in pl.tracks.contains { Self.isSameSong($0, track) } }
    }
}
