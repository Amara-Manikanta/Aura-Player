import SwiftUI

/// Songs picked for you: "Top Picks" (from YouTube's mixes of your favourite songs) and
/// "New for You" (this month's releases ranked by the singers and languages you play).
public struct ForYouView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    public enum Section: String, CaseIterable { case picks = "Top Picks", new = "New for You" }
    @State private var section: Section = .picks
    
    @State private var picks: [RecommendationService.Suggestion] = []
    @State private var generatedAt: Date = .distantPast
    @State private var newItems: [RecommendationService.NewForYou] = []
    @State private var isWorking = false
    @State private var progress: (Int, Int) = (0, 0)
    @State private var notice: String?
    
    /// Inside Discover: the tab is chosen there, so no title or picker here
    private let embedded: Bool
    
    public init(store: PlaylistStore, playback: PlaybackManager, section: Section = .picks, embedded: Bool = false) {
        self.store = store
        self.playback = playback
        self.embedded = embedded
        self._section = State(initialValue: section)
    }
    
    private var pickTracks: [MediaTrack] { picks.map { NewReleasesView.track(from: $0.video) } }
    private var newTracks: [MediaTrack] { newItems.map { NewReleasesView.track(from: $0.release.video) } }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task { await loadPicks(forceNew: false) }
        .task(id: section) { if section == .new && newItems.isEmpty { await loadNew() } }
        .alert("For You", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if !embedded { Text("For You").font(.system(size: 26, weight: .bold)) }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !embedded {
                Picker("", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            
            Button {
                let tracks = section == .picks ? pickTracks : newTracks
                if let first = tracks.first { playback.playTrack(first, inQueue: tracks, context: .none) }
            } label: { Label("Play All", systemImage: "play.fill") }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(isWorking || (section == .picks ? picks.isEmpty : newItems.isEmpty))
            
            Button {
                Task { section == .picks ? await loadPicks(forceNew: true) : await loadNew() }
            } label: { Image(systemName: "arrow.clockwise") }
            .help(section == .picks ? "Find new picks from different favourite songs" : "Check new releases again")
            .disabled(isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, embedded ? 10 : 20)
        .background(.ultraThinMaterial)
    }
    
    private var subtitle: String {
        if isWorking {
            return progress.1 > 0 ? "Learning from your favourite songs… \(progress.0)/\(progress.1)" : "Finding songs for you…"
        }
        switch section {
        case .picks:
            return picks.isEmpty ? "Songs you don't have yet that match what you play"
                : "\(picks.count) songs • based on your most played songs • updated \(generatedAt.formatted(.relative(presentation: .named)))"
        case .new:
            return "\(newItems.count) new songs this month, ranked by the singers and languages you play"
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var content: some View {
        let empty = section == .picks ? picks.isEmpty : newItems.isEmpty
        if isWorking && empty {
            VStack(spacing: 14) {
                Spacer()
                ProgressView(value: Double(progress.0), total: Double(max(progress.1, 1)))
                    .frame(width: 260)
                    .tint(.purple)
                Text(section == .picks
                     ? "Listening to YouTube's mixes of your favourite songs…\nThe first time takes about a minute."
                     : "Checking this month's releases in your languages…")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if empty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Play a few songs and suggestions will appear here.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], spacing: 22) {
                    if section == .picks {
                        ForEach(picks) { s in
                            card(video: s.video, views: 0,
                                 reason: s.seedCount > 1 ? "Like \(s.becauseOf) + \(s.seedCount - 1) more you play" : "Because you like \(s.becauseOf)",
                                 queue: pickTracks)
                        }
                    } else {
                        ForEach(newItems) { n in
                            card(video: n.release.video, views: n.release.views, reason: n.reason, queue: newTracks)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
    
    private func card(video: YouTubeSearchResult, views: Int, reason: String, queue: [MediaTrack]) -> some View {
        ReleaseCard(
            item: YouTubeService.NewRelease(video: video, views: views),
            isCurrent: playback.currentTrack?.youtubeId == video.id,
            isPlaying: playback.isPlaying,
            playlists: store.playlists,
            onPlay: { playback.playTrack(NewReleasesView.track(from: video), inQueue: queue, context: .none) },
            onAdd: { pl in add(NewReleasesView.track(from: video), to: pl) },
            reason: reason,
            onNotInterested: {
                Task {
                    await RecommendationService.shared.markNotInterested(video.id)
                    picks.removeAll { $0.videoId == video.id }
                    newItems.removeAll { $0.id == video.id }
                }
            }
        )
    }
    
    private func add(_ track: MediaTrack, to playlist: Playlist) {
        let name = playlist.name.trimmingCharacters(in: .whitespaces)
        if store.savedSongs(matching: track).contains(where: { $0.playlist.id == playlist.id }) {
            notice = "\"\(track.title)\" is already in \(name)."
        } else {
            store.addTrack(track, to: playlist.id)
            notice = "Added to \(name)."
        }
    }
    
    // MARK: - Loading
    
    /// Uses saved picks (refreshed daily); `forceNew` builds a new set from a different mix of seeds.
    private func loadPicks(forceNew: Bool) async {
        let cached = await RecommendationService.shared.cached()
        if !forceNew, !cached.suggestions.isEmpty {
            picks = cached.suggestions
            generatedAt = cached.generatedAt
            if Date().timeIntervalSince(cached.generatedAt) < 86_400 { return }
        }
        isWorking = true
        progress = (0, 0)
        let seeds = TasteBuilder.seeds(from: store, count: 20)
        let known = TasteBuilder.knownSongs(in: store)
        let knownIds = Set(store.allUniqueTracks.compactMap(\.youtubeId))
        let result = await RecommendationService.shared.generate(seeds: seeds, known: known, knownVideoIds: knownIds) { done, total in
            Task { @MainActor in progress = (done, total) }
        }
        picks = result
        generatedAt = Date()
        isWorking = false
    }
    
    private func loadNew() async {
        isWorking = true
        progress = (0, 0)
        let profile = TasteBuilder.profile(from: store)
        newItems = await RecommendationService.shared.newForYou(profile: profile)
        isWorking = false
    }
}

/// Turns the library into what the recommender needs.
@MainActor
enum TasteBuilder {
    /// How much a song tells us about your taste: plays (log scale), favourite, 👍, played recently.
    static func weight(_ t: MediaTrack, favorite: Bool) -> Double {
        var w = log2(1 + Double(t.totalPlays))
        if favorite { w += 1.5 }
        if let vid = t.youtubeId, !t.originalURL.lowercased().hasPrefix("http"), !vid.isEmpty { w += 0.5 }  // 👍 / chosen video
        if let last = t.lastPlayedDate, Date().timeIntervalSince(last) < 30 * 86_400 { w += 1 }
        return w
    }
    
    /// About `count` seed songs: strongest first, but sampled from the top 60 so each refresh differs,
    /// and at most 2 per artist and per movie so one favourite doesn't take over.
    static func seeds(from store: PlaylistStore, count: Int) -> [RecommendationService.Seed] {
        let ranked = store.allUniqueTracks
            .filter { $0.sourceType == .youtube }
            .map { ($0, weight($0, favorite: store.isFavorite(track: $0))) }
            .filter { $0.1 > 1 }
            .sorted { $0.1 > $1.1 }
        var perArtist: [String: Int] = [:], perMovie: [String: Int] = [:]
        var pool: [(MediaTrack, Double)] = []
        for (t, w) in ranked {
            let artist = ArtistPhotoService.normalize(PlaylistStore.splitArtists(t.artist).first ?? t.artist)
            let movie = ArtistPhotoService.normalize(t.movieName ?? "")
            if perArtist[artist, default: 0] >= 2 { continue }
            if !movie.isEmpty && perMovie[movie, default: 0] >= 2 { continue }
            perArtist[artist, default: 0] += 1
            if !movie.isEmpty { perMovie[movie, default: 0] += 1 }
            pool.append((t, w))
            if pool.count >= 60 { break }
        }
        // weighted random pick without replacement
        var chosen: [RecommendationService.Seed] = []
        var remaining = pool
        while chosen.count < count && !remaining.isEmpty {
            let total = remaining.reduce(0) { $0 + $1.1 }
            var r = Double.random(in: 0..<max(total, 0.001))
            var index = 0
            for (i, item) in remaining.enumerated() {
                r -= item.1
                if r <= 0 { index = i; break }
            }
            let item = remaining.remove(at: index)
            chosen.append(RecommendationService.Seed(track: item.0, weight: item.1))
        }
        return chosen
    }
    
    static func knownSongs(in store: PlaylistStore) -> [RecommendationService.KnownSong] {
        store.allUniqueTracks.compactMap { t in
            let key = YouTubeService.translit(t.coreTitle)   // spelling-tolerant, like the video titles it's compared with
            guard key.count >= 5 else { return nil }
            var context = PlaylistStore.splitArtists(t.artist).map { YouTubeService.translit($0) }.filter { $0.count >= 4 }
            if let movie = t.movieName.map(YouTubeService.translit), movie.count >= 3 { context.append(movie) }
            return RecommendationService.KnownSong(key: key, context: context)
        }
    }
    
    static func profile(from store: PlaylistStore) -> RecommendationService.TasteProfile {
        let artists = store.allArtists.filter { $0.totalPlayCount > 0 }
        let maxPlays = Double(artists.map(\.totalPlayCount).max() ?? 1)
        var weights: [String: Double] = [:], display: [String: String] = [:], words: [String: [String]] = [:]
        for a in artists {
            let key = ArtistPhotoService.normalize(a.name)
            weights[key] = log2(1 + Double(a.totalPlayCount)) / log2(1 + maxPlays)
            display[key] = a.name
            words[key] = a.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        var langPlays: [String: Double] = [:]
        for t in store.allUniqueTracks where t.totalPlays > 0 {
            let lang = t.releaseLanguage ?? (t.genre?.lowercased() == "bollywood" ? "hindi" : (t.isIndianRelease ? nil : "english"))
            if let lang { langPlays[lang, default: 0] += Double(t.totalPlays) }
        }
        let total = max(langPlays.values.reduce(0, +), 1)
        let languages = langPlays.map { ($0.key, $0.value / total) }.sorted { $0.1 > $1.1 }
        return .init(artistWeights: weights, artistDisplay: display, artistWords: words, languages: languages)
    }
}
