import SwiftUI

/// Discover, like the Mac app: "Top Picks" (from YouTube's mixes of your favourite songs),
/// "New for You" (this month's releases ranked by the singers and languages you play) and all New Releases.
public struct ForYouView: View {
    @ObservedObject var store: PlaylistStore
    @ObservedObject var playback: PlaybackManager

    enum Tab: String, CaseIterable {
        case picks = "Top Picks"
        case newForYou = "New for You"
        case releases = "New Releases"
    }
    @AppStorage("discoverTab") private var tab: Tab = .picks

    @State private var picks: [RecommendationService.Suggestion] = []
    @State private var generatedAt: Date = .distantPast
    @State private var newItems: [RecommendationService.NewForYou] = []
    @State private var isWorking = false
    @State private var progress: (Int, Int) = (0, 0)
    @State private var trackForPlaylistSheet: MediaTrack?

    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }

    private var pickTracks: [MediaTrack] { picks.map { DiscoverRow.track(from: $0.video) } }
    private var newTracks: [MediaTrack] { newItems.map { DiscoverRow.track(from: $0.release.video) } }

    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    switch tab {
                    case .picks, .newForYou:
                        suggestions
                    case .releases:
                        NewReleasesView(playlistStore: store, playback: playback)
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $trackForPlaylistSheet) { t in
                AddToPlaylistSheet(track: t, playlistStore: store)
            }
            .task { await loadPicks(forceNew: false) }
            .task(id: tab) { if tab == .newForYou && newItems.isEmpty { await loadNew() } }
        }
    }

    // MARK: - Top Picks / New for You

    private var subtitle: String {
        if isWorking {
            return progress.1 > 0 ? "Learning from your favourite songs… \(progress.0)/\(progress.1)" : "Finding songs for you…"
        }
        if tab == .picks {
            return picks.isEmpty ? "Songs you don't have yet that match what you play"
                : "\(picks.count) songs • updated \(generatedAt.formatted(.relative(presentation: .named)))"
        }
        return "\(newItems.count) new songs this month, ranked by your singers and languages"
    }

    @ViewBuilder
    private var suggestions: some View {
        let isPicks = tab == .picks
        let tracks = isPicks ? pickTracks : newTracks
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AuraTheme.textTertiary)
                    .lineLimit(2)
                Spacer()
                Button {
                    Haptics.light()
                    Task { isPicks ? await loadPicks(forceNew: true) : await loadNew() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AuraTheme.primary)
                        .frame(width: 34, height: 34)
                        .background(AuraTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .disabled(isWorking)
                Button {
                    Haptics.medium()
                    if let first = tracks.first { playback.playTrack(first, inQueue: tracks, context: .none) }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AuraTheme.primaryGradient)
                        .clipShape(Capsule())
                }
                .disabled(tracks.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if isWorking && tracks.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView(value: Double(progress.0), total: Double(max(progress.1, 1)))
                        .frame(width: 220)
                        .tint(AuraTheme.primary)
                    Text(isPicks ? "Listening to YouTube's mixes of your favourite songs…\nThe first time takes about a minute."
                                 : "Checking this month's releases in your languages…")
                        .font(.system(size: 13))
                        .foregroundColor(AuraTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 40)).foregroundColor(AuraTheme.textTertiary)
                    Text("Play a few songs and suggestions will appear here.")
                        .font(.system(size: 13))
                        .foregroundColor(AuraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        if isPicks {
                            ForEach(Array(picks.enumerated()), id: \.element.id) { i, s in
                                row(video: s.video, track: tracks[i], queue: tracks,
                                    reason: s.seedCount > 1 ? "Like \(s.becauseOf) + \(s.seedCount - 1) more" : "Because you like \(s.becauseOf)")
                            }
                        } else {
                            ForEach(Array(newItems.enumerated()), id: \.element.id) { i, n in
                                row(video: n.release.video, track: tracks[i], queue: tracks, reason: n.reason,
                                    views: n.release.views, uploadedAgo: n.release.uploadedAgo)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .refreshable { isPicks ? await loadPicks(forceNew: true) : await loadNew() }
            }
        }
    }

    private func row(video: YouTubeSearchResult, track: MediaTrack, queue: [MediaTrack], reason: String,
                     views: Int = 0, uploadedAgo: String = "") -> some View {
        DiscoverRow(
            video: video, track: track, reason: reason, views: views, uploadedAgo: uploadedAgo,
            isCurrent: playback.currentTrack?.youtubeId == video.id,
            isPlaying: playback.isPlaying,
            onPlay: { playback.playTrack(track, inQueue: queue, context: .none) },
            onAdd: { trackForPlaylistSheet = track },
            onNotInterested: {
                Task {
                    await RecommendationService.shared.markNotInterested(video.id)
                    picks.removeAll { $0.videoId == video.id }
                    newItems.removeAll { $0.id == video.id }
                }
            }
        )
    }

    // MARK: - Loading

    /// Uses saved picks (refreshed daily); `forceNew` builds a new set from a different mix of seeds.
    private func loadPicks(forceNew: Bool) async {
        guard !isWorking else { return }
        let cached = await RecommendationService.shared.cached()
        if !forceNew, !cached.suggestions.isEmpty {
            picks = cached.suggestions
            generatedAt = cached.generatedAt
            if Date().timeIntervalSince(cached.generatedAt) < 86_400 { return }
        }
        isWorking = true
        progress = (0, 0)
        // The number-crunching over 3,000+ songs runs off the main thread: it used to freeze the app
        let tracks = store.allUniqueTracks
        let favorites = store.favoritesPlaylist?.tracks ?? []
        let (seeds, known, knownIds) = await Task.detached(priority: .userInitiated) {
            (TasteBuilder.seeds(tracks: tracks, favorites: favorites, count: 20),
             TasteBuilder.knownSongs(tracks: tracks),
             Set(tracks.compactMap(\.youtubeId)))
        }.value
        let result = await RecommendationService.shared.generate(seeds: seeds, known: known, knownVideoIds: knownIds) { done, total in
            Task { @MainActor in progress = (done, total) }
        }
        if !result.isEmpty {
            picks = result
            generatedAt = Date()
        }
        isWorking = false
    }

    private func loadNew() async {
        guard !isWorking else { return }
        isWorking = true
        progress = (0, 0)
        let tracks = store.allUniqueTracks
        let artists = store.allArtists
        let profile = await Task.detached(priority: .userInitiated) {
            TasteBuilder.profile(tracks: tracks, artists: artists)
        }.value
        newItems = await RecommendationService.shared.newForYou(profile: profile)
        isWorking = false
    }
}

/// Turns the library into what the recommender needs (same as the Mac app).
/// Works on plain arrays so it can run off the main thread.
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
    static func seeds(tracks: [MediaTrack], favorites: [MediaTrack], count: Int) -> [RecommendationService.Seed] {
        let favoriteIds = Set(favorites.map(\.id))
        let favoriteVideos = Set(favorites.compactMap(\.youtubeId))
        let ranked = tracks
            .filter { $0.sourceType == .youtube }
            .map { t -> (MediaTrack, Double) in
                let isFavorite = favoriteIds.contains(t.id) || (t.youtubeId.map(favoriteVideos.contains) ?? false)
                return (t, weight(t, favorite: isFavorite))
            }
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

    static func knownSongs(tracks: [MediaTrack]) -> [RecommendationService.KnownSong] {
        tracks.compactMap { t in
            let key = YouTubeService.translit(t.coreTitle)   // spelling-tolerant, like the video titles it's compared with
            guard key.count >= 5 else { return nil }
            var context = PlaylistStore.splitArtists(t.artist).map { YouTubeService.translit($0) }.filter { $0.count >= 4 }
            if let movie = t.movieName.map(YouTubeService.translit), movie.count >= 3 { context.append(movie) }
            return RecommendationService.KnownSong(key: key, context: context)
        }
    }

    static func profile(tracks: [MediaTrack], artists allArtists: [ArtistGroup]) -> RecommendationService.TasteProfile {
        let artists = allArtists.filter { $0.totalPlayCount > 0 }
        let maxPlays = Double(artists.map(\.totalPlayCount).max() ?? 1)
        var weights: [String: Double] = [:], display: [String: String] = [:], words: [String: [String]] = [:]
        for a in artists {
            let key = ArtistPhotoService.normalize(a.name)
            weights[key] = log2(1 + Double(a.totalPlayCount)) / log2(1 + maxPlays)
            display[key] = a.name
            words[key] = a.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        var langPlays: [String: Double] = [:]
        for t in tracks where t.totalPlays > 0 {
            let lang = t.releaseLanguage ?? (t.genre?.lowercased() == "bollywood" ? "hindi" : (t.isIndianRelease ? nil : "english"))
            if let lang { langPlays[lang, default: 0] += Double(t.totalPlays) }
        }
        let total = max(langPlays.values.reduce(0, +), 1)
        let languages = langPlays.map { ($0.key, $0.value / total) }.sorted { $0.1 > $1.1 }
        return .init(artistWeights: weights, artistDisplay: display, artistWords: words, languages: languages)
    }
}
