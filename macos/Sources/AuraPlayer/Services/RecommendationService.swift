import Foundation

/// "For You": songs you don't have yet that match what you actually listen to.
///
/// How it works:
/// 1. Seeds: your most-played / favourite / 👍 / recently played songs (varied across artists & movies).
/// 2. For each seed, YouTube's own "Mix" (the radio YouTube builds from one song, based on what
///    millions of listeners play together).
/// 3. Songs that show up in several of your seeds' mixes, near the top, score highest.
/// 4. Anything already in your library, marked "Not interested", or junk is removed.
public actor RecommendationService {
    public static let shared = RecommendationService()

    public struct Suggestion: Codable, Identifiable, Hashable, Sendable {
        public var id: String { videoId }
        public let videoId: String
        public let title: String
        public let channel: String
        public let duration: Double
        public let score: Double
        /// The song of yours that led here ("Because you like …")
        public let becauseOf: String
        /// How many of your seed songs led to this one
        public let seedCount: Int

        public var video: YouTubeSearchResult {
            YouTubeSearchResult(id: videoId, title: title, channel: channel, duration: duration,
                                thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
                                url: "https://www.youtube.com/watch?v=\(videoId)")
        }
    }

    /// A song of yours used as a starting point, with how much it counts
    public struct Seed: Sendable {
        let track: MediaTrack
        let weight: Double
    }

    /// A saved song, reduced to what's needed to recognise it in a YouTube title
    public struct KnownSong: Sendable {
        let key: String            // normalized song name
        let context: [String]      // normalized movie / singer names
    }

    private struct Saved: Codable {
        var generatedAt: Date
        var suggestions: [Suggestion]
        var notInterested: [String]          // video ids
        var seedVideoIds: [String: String]   // seed track key → resolved video id
    }

    private var saved: Saved
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AuraPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("for_you.json")
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = s
        } else {
            saved = Saved(generatedAt: .distantPast, suggestions: [], notInterested: [], seedVideoIds: [:])
        }
    }

    // MARK: - Public

    public func cached() -> (suggestions: [Suggestion], generatedAt: Date) {
        (saved.suggestions.filter { !saved.notInterested.contains($0.videoId) }, saved.generatedAt)
    }

    public func markNotInterested(_ videoId: String) {
        if !saved.notInterested.contains(videoId) { saved.notInterested.append(videoId) }
        saved.suggestions.removeAll { $0.videoId == videoId }
        persist()
    }

    /// Builds fresh suggestions. `progress(done, total)` reports seed songs processed.
    public func generate(seeds: [Seed], known: [KnownSong], knownVideoIds: Set<String>,
                         progress: @escaping @Sendable (Int, Int) -> Void) async -> [Suggestion] {
        let blocked = Set(saved.notInterested)
        let total = seeds.count
        var done = 0

        // 1. A YouTube video for every seed (remembered between runs: lookups are the slow part)
        var seedIds: [(Seed, String)] = []
        for seed in seeds {
            let key = Self.trackKey(seed.track)
            var vid = seed.track.youtubeId ?? saved.seedVideoIds[key]
            if vid == nil {
                vid = await YouTubeService.shared.fastResolveVideoId(
                    for: seed.track.videoSearchQuery, songTitle: seed.track.title, artist: seed.track.artist,
                    movie: seed.track.movieName, expectedDuration: seed.track.duration, language: nil)
                if let vid { saved.seedVideoIds[key] = vid }
            }
            if let vid { seedIds.append((seed, vid)) }
            done += 1
            progress(done / 2, total)   // first half of the progress bar
        }
        persist()

        // 2. Their mixes, a few at a time (each is a separate yt-dlp run)
        var mixes: [(Seed, [MixEntry])] = []
        await withTaskGroup(of: (Int, [MixEntry]).self) { group in
            var next = 0
            func addNext() {
                guard next < seedIds.count else { return }
                let index = next, vid = seedIds[next].1
                group.addTask { (index, Self.fetchMix(videoId: vid)) }
                next += 1
            }
            for _ in 0..<4 { addNext() }
            var finished = 0
            for await (index, entries) in group {
                mixes.append((seedIds[index].0, entries))
                finished += 1
                progress(total / 2 + finished * (total - total / 2) / max(seedIds.count, 1), total)
                addNext()
            }
        }

        // 3. Score: weight of the seed × how near the top of its mix; summed across seeds
        struct Candidate { var entry: MixEntry; var score: Double; var bestSeed: String; var bestContribution: Double; var seeds: Set<String> }
        var candidates: [String: Candidate] = [:]   // keyed by song identity, not video, to merge re-uploads
        for (seed, entries) in mixes {
            for (position, entry) in entries.enumerated() where position > 0 {   // position 0 is the seed itself
                guard !knownVideoIds.contains(entry.id), !blocked.contains(entry.id),
                      Self.isGoodSong(entry), !Self.isKnown(entry.title, known: known) else { continue }
                let contribution = seed.weight * max(0.15, 1.0 - Double(position) / 30.0)
                let songKey = Self.songIdentity(entry.title)
                let seedName = seed.track.coreTitle
                if var c = candidates[songKey] {
                    c.score += contribution
                    c.seeds.insert(seedName)
                    if contribution > c.bestContribution { c.bestContribution = contribution; c.bestSeed = seedName }
                    // prefer the official-looking upload of the same song
                    if Self.uploadQuality(entry) > Self.uploadQuality(c.entry) { c.entry = entry }
                    candidates[songKey] = c
                } else {
                    candidates[songKey] = Candidate(entry: entry, score: contribution, bestSeed: seedName,
                                                    bestContribution: contribution, seeds: [seedName])
                }
            }
        }

        // Songs recommended by several of your favourites count extra
        let ranked = candidates.values
            .map { c in (c, c.score * (1 + 0.35 * Double(c.seeds.count - 1)) + Self.uploadQuality(c.entry) * 0.3) }
            .sorted { $0.1 > $1.1 }

        // 4. Variety: at most 4 songs per channel in the list
        var perChannel: [String: Int] = [:], perSeed: [String: Int] = [:]
        var chosenIdentities: [String] = []
        var result: [Suggestion] = []
        for (c, score) in ranked {
            let channel = c.entry.channel.lowercased()
            let identity = Self.songIdentity(c.entry.title)
            // every favourite gets a voice (so English / Hindi seeds aren't drowned out by Telugu ones)
            guard perChannel[channel, default: 0] < 4, perSeed[c.bestSeed, default: 0] < 4,
                  !Self.isDuplicate(identity, of: chosenIdentities) else { continue }
            perChannel[channel, default: 0] += 1
            perSeed[c.bestSeed, default: 0] += 1
            chosenIdentities.append(identity)
            result.append(Suggestion(videoId: c.entry.id, title: c.entry.title, channel: c.entry.channel,
                                     duration: c.entry.duration, score: score, becauseOf: c.bestSeed, seedCount: c.seeds.count))
            if result.count >= 60 { break }
        }

        saved.suggestions = result
        saved.generatedAt = Date()
        persist()
        AppLog.log("foryou", "\(seeds.count) seeds, \(mixes.count) mixes, \(candidates.count) candidates → \(result.count) suggestions")
        for s in result.prefix(10) {
            AppLog.log("foryou", String(format: "  %.1f (%d seeds) %@ ← %@", s.score, s.seedCount, s.title, s.becauseOf))
        }
        return result
    }

    // MARK: - New releases ranked by taste
    
    /// What you listen to: singers/composers weighted by plays, and your languages by share of plays.
    public struct TasteProfile: Sendable {
        public let artistWeights: [String: Double]   // normalized name → weight (plays-based)
        public let artistDisplay: [String: String]   // normalized name → display name
        public let artistWords: [String: [String]]   // normalized name → its words ("sid", "sriram")
        public let languages: [(String, Double)]     // e.g. [("telugu", 0.55), ("hindi", 0.2)]
    }
    
    public struct NewForYou: Identifiable, Hashable, Sendable {
        public var id: String { release.id }
        public let release: YouTubeService.NewRelease
        public let score: Double
        public let reason: String
    }
    
    /// This month's new songs in your languages, best taste match first.
    public func newForYou(profile: TasteProfile) async -> [NewForYou] {
        let blocked = Set(saved.notInterested)
        var results: [NewForYou] = []
        var seen = Set<String>()
        // Your main languages (at least 5% of your plays), up to 4
        let languages = profile.languages.filter { $0.1 >= 0.05 }.prefix(4)
        for (language, share) in languages {
            let releases = (try? await YouTubeService.shared.newReleases(language: language.capitalized, period: .month)) ?? []
            for r in releases where !blocked.contains(r.id) && seen.insert(r.id).inserted {
                // Whole words only: "Karthik" must not match "Karthika", nor "Priya" match "Priyanka"
                let words = Set((r.video.title + " " + r.video.channel).lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                var matched: [(String, Double)] = []
                for (name, weight) in profile.artistWeights {
                    guard let parts = profile.artistWords[name], !parts.isEmpty, name.count >= 5 else { continue }
                    // one-word names like "Priya" or "Rahul" are part of many other people's names
                    if parts.count == 1 && name.count < 7 { continue }
                    if parts.allSatisfy({ words.contains($0) }) { matched.append((name, weight)) }
                }
                matched.sort { $0.1 > $1.1 }
                let artistScore = matched.prefix(3).reduce(0) { $0 + $1.1 }
                let popularity = log10(Double(max(r.views, 1)))   // 3 … 7
                let t = r.video.title.lowercased()
                var quality = 0.0
                if ["video song", "full video", "official video", "music video", "- video", "(video)"].contains(where: { t.contains($0) }) { quality += 1 }
                if t.contains("lyric") { quality -= 1.5 }
                if t.contains("audio") { quality -= 1 }
                let score = artistScore * 2 + share * 6 + popularity * 0.6 + quality
                let reason: String
                if let top = matched.first {
                    reason = "You listen to \(profile.artistDisplay[top.0] ?? top.0)"
                } else {
                    reason = "New in \(language.capitalized)"
                }
                results.append(NewForYou(release: r, score: score, reason: reason))
            }
        }
        results.sort { $0.score > $1.score }
        // one upload per song (the best-scored: usually the real video, not the lyrical / re-uploads)
        var identities: [String] = []
        results = results.filter { item in
            let id = Self.songIdentity(item.release.video.title)
            if Self.isDuplicate(id, of: identities) { return false }
            identities.append(id)
            return true
        }
        AppLog.log("foryou", "new for you: \(results.count) releases in \(languages.map(\.0))")
        return results
    }
    
    // MARK: - YouTube Mix

    struct MixEntry: Sendable {
        let id: String
        let title: String
        let channel: String
        let duration: Double
    }

    /// YouTube's "Mix" for a song: list=RD<id> (no sign-in needed)
    static func fetchMix(videoId: String) -> [MixEntry] {
        let binaries = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        guard let binary = binaries.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--flat-playlist", "--dump-single-json", "--no-warnings", "--playlist-end", "30",
                             "https://www.youtube.com/watch?v=\(videoId)&list=RD\(videoId)"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { e in
            guard let id = e["id"] as? String, let title = e["title"] as? String else { return nil }
            return MixEntry(id: id, title: title,
                            channel: (e["channel"] as? String) ?? (e["uploader"] as? String) ?? "YouTube",
                            duration: (e["duration"] as? Double) ?? 0)
        }
    }

    // MARK: - Filters

    /// Real songs only: no jukeboxes, lyric/remix/cover versions, live shows, Shorts, long compilations.
    static func isGoodSong(_ e: MixEntry) -> Bool {
        let t = e.title.lowercased()
        if e.duration > 0 && (e.duration < 90 || e.duration > 600) { return false }
        let junk = ["jukebox", "lyric", "lyrical", "karaoke", "cover", "remix", "mashup", "slowed", "reverb", "8d",
                    "lofi", "lo-fi", "bgm", "instrumental", "reaction", "live", "performance", "trailer", "teaser",
                    "promo", "status", "#shorts", "nonstop", "back to back", "audio songs", "full album", "hour",
                    "extended", "amv", "edit", "version", "versión", "sped up", "nightcore", "tiktok", "ringtone"]
        return !junk.contains(where: { t.contains($0) })
    }

    /// Already in your library? (same song name, plus its movie or a singer in the video title)
    static func isKnown(_ title: String, known: [KnownSong]) -> Bool {
        let t = YouTubeService.translit(title)   // "Chinnadana" == "Chinnadhana"
        for song in known where t.contains(song.key) {
            if song.context.isEmpty || song.context.contains(where: { t.contains($0) }) { return true }
        }
        return false
    }

    /// Same song across different uploads: the first part of the title ("Hoyna Hoyna" from "Hoyna Hoyna | Gang Leader")
    static func songIdentity(_ title: String) -> String {
        var t = title.lowercased()
        for separator in ["|", "(", "[", " - video", " - full", " - lyric", " - audio"] {
            if let r = t.range(of: separator), r.lowerBound > t.startIndex { t = String(t[..<r.lowerBound]) }
        }
        if let colon = t.range(of: ":"), colon.upperBound < t.endIndex { t = String(t[colon.upperBound...]) }  // "The Paradise: Sammakka"
        let generic = ["full video song", "video song", "full video", "full song", "lyrical song", "lyrical video", "lyric video",
                       "lyrical", "lyric", "audio song", "audio", "official video", "music video", "video", "song", "full", "4k", "8k", "hd"]
        for g in generic { t = t.replacingOccurrences(of: g, with: " ") }
        return YouTubeService.translit(t)
    }
    
    /// Same song as one already chosen? (one identity contains the other)
    static func isDuplicate(_ identity: String, of chosen: [String]) -> Bool {
        guard identity.count >= 4 else { return chosen.contains(identity) }
        return chosen.contains { $0 == identity || ($0.count >= 4 && ($0.contains(identity) || identity.contains($0))) }
    }

    static func uploadQuality(_ e: MixEntry) -> Double {
        let t = e.title.lowercased(), c = e.channel.lowercased()
        var q = 0.0
        if ["vevo", "t-series", "sony music", "zee music", "saregama", "aditya music", "lahari", "mango music",
            "think music", "tips", "yrf", "speed records", "sun tv"].contains(where: { c.contains($0) }) { q += 2 }
        if ["video song", "official video", "music video", "full video"].contains(where: { t.contains($0) }) { q += 1 }
        return q
    }

    static func trackKey(_ t: MediaTrack) -> String {
        "\(ArtistPhotoService.normalize(t.coreTitle))|\(ArtistPhotoService.normalize(t.artist))"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: fileURL, options: .atomic) }
    }
}
