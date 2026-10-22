import Foundation

public enum TrackSourceType: String, Codable, Sendable {
    case local
    case youtube
}

public enum MediaType: String, Codable, Sendable {
    case audio
    case video
}

public struct MediaTrack: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var duration: TimeInterval
    public var sourceType: TrackSourceType
    public var mediaType: MediaType
    public var originalURL: String
    public var streamURL: String?
    public var thumbnailURL: String?
    public var isFavorite: Bool
    public var dateAdded: Date
    public var youtubeId: String?
    public var playCount: Int
    public var lastPlayedDate: Date?
    /// Album as named in Apple Music, e.g. "Gabbar Singh (Original Motion Picture Soundtrack) - EP"
    public var album: String?
    public var composer: String?
    public var year: Int?
    /// Apple Music genre, e.g. "Telugu", "Bollywood", "Regional Indian"
    public var genre: String?
    /// Plays counted by the Apple Music app (synced with "Update Song Details")
    public var applePlayCount: Int?
    /// Optional trim: playback starts at `startTime` and moves on at `endTime` (seconds)
    public var startTime: Double?
    public var endTime: Double?
    /// Videos the user marked as wrong (👎) for this song; never picked again
    public var rejectedVideoIds: [String]?
    
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Unknown Artist",
        duration: TimeInterval = 0,
        sourceType: TrackSourceType,
        mediaType: MediaType = .audio,
        originalURL: String,
        streamURL: String? = nil,
        thumbnailURL: String? = nil,
        isFavorite: Bool = false,
        dateAdded: Date = Date(),
        youtubeId: String? = nil,
        playCount: Int = 0,
        lastPlayedDate: Date? = nil,
        album: String? = nil,
        composer: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.sourceType = sourceType
        self.mediaType = mediaType
        self.originalURL = originalURL
        self.streamURL = streamURL
        self.thumbnailURL = thumbnailURL
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
        self.youtubeId = youtubeId
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.album = album
        self.composer = composer
        self.year = year
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? "Unknown Artist"
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        self.sourceType = try container.decode(TrackSourceType.self, forKey: .sourceType)
        self.mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .audio
        self.originalURL = try container.decode(String.self, forKey: .originalURL)
        self.streamURL = try container.decodeIfPresent(String.self, forKey: .streamURL)
        self.thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        self.youtubeId = try container.decodeIfPresent(String.self, forKey: .youtubeId)
        self.playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        self.lastPlayedDate = try container.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
        self.album = try container.decodeIfPresent(String.self, forKey: .album)
        self.composer = try container.decodeIfPresent(String.self, forKey: .composer)
        self.year = try container.decodeIfPresent(Int.self, forKey: .year)
        self.genre = try container.decodeIfPresent(String.self, forKey: .genre)
        self.applePlayCount = try container.decodeIfPresent(Int.self, forKey: .applePlayCount)
        self.startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        self.rejectedVideoIds = try container.decodeIfPresent([String].self, forKey: .rejectedVideoIds)
    }
    
    /// Copy of this track with a fresh identity (used when the same track would appear twice in one list).
    public func withNewId() -> MediaTrack {
        MediaTrack(
            title: title, artist: artist, duration: duration, sourceType: sourceType,
            mediaType: mediaType, originalURL: originalURL, streamURL: streamURL,
            thumbnailURL: thumbnailURL, isFavorite: isFavorite, dateAdded: dateAdded,
            youtubeId: youtubeId, playCount: playCount, lastPlayedDate: lastPlayedDate,
            album: album, composer: composer, year: year
        ).withTrim(start: startTime, end: endTime).withGenre(genre).withRejected(rejectedVideoIds).withApplePlays(applePlayCount)
    }
    
    func withApplePlays(_ n: Int?) -> MediaTrack {
        var copy = self
        copy.applePlayCount = n
        return copy
    }
    
    /// Plays in Apple Music plus plays in AuraPlayer
    public var totalPlays: Int { (applePlayCount ?? 0) + playCount }
    
    func withRejected(_ ids: [String]?) -> MediaTrack {
        var copy = self
        copy.rejectedVideoIds = ids
        return copy
    }
    
    func withGenre(_ g: String?) -> MediaTrack {
        var copy = self
        copy.genre = g
        return copy
    }
    
    func withTrim(start: Double?, end: Double?) -> MediaTrack {
        var copy = self
        copy.startTime = start
        copy.endTime = end
        return copy
    }
    
    /// "0:15 – 3:40" when the song is trimmed, otherwise nil
    public var trimLabel: String? {
        guard (startTime ?? 0) > 0 || endTime != nil else { return nil }
        func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        return "\(fmt(startTime ?? 0)) – \(endTime.map(fmt) ?? "end")"
    }
    
    /// Movie / album name cleaned for searching: "Gabbar Singh (Original Motion Picture Soundtrack) - EP"
    /// becomes "Gabbar Singh"; falls back to `Song (From "Movie")` in the title.
    public var movieName: String? {
        // `Song (From "Movie")` is the most reliable; albums can be compilations like "Best of Shaan"
        if let r = title.range(of: #"From \"([^\"]+)\""#, options: .regularExpression) {
            let movie = String(title[r]).replacingOccurrences(of: "From ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            // "They Call Him OG (Kannada)" → "They Call Him OG"
            return Self.removingBrackets(movie)
        }
        if let album, !album.isEmpty {
            // "24 (Telugu) [Original Motion Picture Soundtrack]" → "24"
            var a = Self.removingBrackets(album)
            for suffix in [" - EP", " - Single", " - Original Soundtrack"] {
                if a.hasSuffix(suffix) { a = String(a.dropLast(suffix.count)) }
            }
            a = a.trimmingCharacters(in: .whitespacesAndNewlines)
            // Single releases are named after the song itself, which says nothing about the movie
            if !a.isEmpty && a.lowercased() != coreTitle.lowercased() { return a }
        }
        if let r = title.range(of: #"From \"([^\"]+)\""#, options: .regularExpression) {
            return String(title[r]).replacingOccurrences(of: "From ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }
    
    static func removingBrackets(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static let indianLanguages = ["telugu", "tamil", "hindi", "kannada", "malayalam", "bengali", "marathi", "punjabi"]
    private static let indianGenres = ["telugu", "tamil", "hindi", "kannada", "malayalam", "bollywood", "tollywood",
                                       "regional indian", "indian", "indian pop", "indian classical", "punjabi"]
    
    /// Language this release is in, from "(Kannada)" / "Telugu Version" markers or the genre.
    public var releaseLanguage: String? {
        let text = "\(title) \(album ?? "")".lowercased()
        if let lang = Self.indianLanguages.first(where: { text.contains($0) }) { return lang }
        if let g = genre?.lowercased(), Self.indianLanguages.contains(g) { return g }
        return nil
    }
    
    /// Whether this is an Indian film/regional song, where dubbed versions in other languages exist.
    public var isIndianRelease: Bool {
        if releaseLanguage != nil { return true }
        guard let g = genre?.lowercased() else { return false }
        return Self.indianGenres.contains(g)
    }
    
    /// Language to search in: the user's preferred language for Indian releases, otherwise none.
    public var searchLanguage: String? {
        guard isIndianRelease,
              let preferred = UserDefaults.standard.string(forKey: "preferredLanguage")?.lowercased(),
              !preferred.isEmpty, preferred != "none" else { return nil }
        return preferred
    }
    
    /// Song name without "(From "Movie")" style suffixes.
    public var coreTitle: String {
        var t = title
        if let r = t.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) { t.removeSubrange(r) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// What to type into YouTube to find this song's video: "Pillaa Gabbar Singh".
    public var videoSearchQuery: String {
        if originalURL.lowercased().hasPrefix("http") || sourceType == .local {
            return "\(coreTitle) \(artist)"
        }
        // Film songs: the movie identifies the song best. Everything else: the artist
        // (an album like "Until Now" says little, and leaving the artist out lets covers win).
        if isIndianRelease, let movie = movieName { return "\(coreTitle) \(movie)" }
        // Drop credits like "(Acoustic Rishbh)" from the artist
        var cleanArtist = artist
        if let r = cleanArtist.range(of: #"\s*\(.*?\)"#, options: .regularExpression) { cleanArtist.removeSubrange(r) }
        return "\(coreTitle) \(cleanArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
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
