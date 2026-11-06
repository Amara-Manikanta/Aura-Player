import SwiftUI

public enum SearchScope: String, CaseIterable, Identifiable {
    case music = "Music"
    case youtube = "YouTube Direct"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .music: return "music.note"
        case .youtube: return "play.rectangle.fill"
        }
    }
}

public struct SearchView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var searchText: String = ""
    @State private var searchScope: SearchScope = .music
    @State private var isSearching: Bool = false
    @State private var searchResults: [YouTubeSearchResult] = []
    @State private var suggestions: [String] = []
    @State private var trackForPlaylistSheet: MediaTrack?
    @State private var suggestionTask: Task<Void, Never>?
    /// YouTube search, before anything is typed: a feed per topic (Home, Tech, Music...), like YouTube's own tabs
    @State private var feedTab: String = "Home"
    @State private var feeds: [String: [YouTubeSearchResult]] = [:]
    @State private var feedLoading = false
    /// Version of the song to look for ("Any" = no preference), as on the Mac
    @AppStorage("searchLanguage") private var searchLanguage: String = "Any"
    private let languages = ["Any", "Telugu", "Hindi", "Tamil", "Kannada", "Malayalam", "English", "Punjabi"]
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    private let quickTags = ["Devotional Songs", "Ayyappa Swamy", "Top Hits", "Telugu Hits", "Lo-Fi Chill", "Bollywood", "Shiv Stuti"]
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                VStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AuraTheme.textTertiary)
                        
                        TextField("Search songs, artists, or paste YouTube link...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(AuraTheme.textPrimary)
                            .autocorrectionDisabled()
                            .onSubmit {
                                performSearch(query: searchText)
                            }
                            .onChange(of: searchText) { newValue in
                                fetchSuggestions(for: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                                suggestions = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AuraTheme.textTertiary)
                            }
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Search Scope Selector (Music / YouTube Direct)
                    HStack(spacing: 6) {
                        ForEach(SearchScope.allCases) { scope in
                            scopeButton(scope)
                        }
                    }
                    .padding(4)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)
                    
                    // Language of the version to find (re-runs the search); only the Music search uses it
                    if searchScope == .music {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(languages, id: \.self) { lang in
                                Button {
                                    searchLanguage = lang
                                    if !searchText.isEmpty { performSearch(query: searchText) }
                                } label: {
                                    Text(lang)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(searchLanguage == lang ? AuraTheme.primary : AuraTheme.surfaceElevated)
                                        .foregroundColor(searchLanguage == lang ? .white : AuraTheme.textSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    }
                    
                    // Suggestions Overlay (if typing and no results yet)
                    if !suggestions.isEmpty && searchResults.isEmpty && !isSearching {
                        VStack(spacing: 0) {
                            ForEach(suggestions.prefix(5), id: \.self) { sug in
                                Button {
                                    Haptics.light()
                                    searchText = sug
                                    suggestions = []
                                    performSearch(query: sug)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 13))
                                            .foregroundColor(AuraTheme.textTertiary)
                                        Text(sug)
                                            .font(.system(size: 15))
                                            .foregroundColor(AuraTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.system(size: 12))
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(AuraTheme.glassBorder)
                            }
                        }
                        .liquidGlass(cornerRadius: 12)
                        .padding(.horizontal, 16)
                    }
                    
                    // Quick Filter Chips (if idle)
                    if searchResults.isEmpty && !isSearching && suggestions.isEmpty && searchScope == .music {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickTags, id: \.self) { tag in
                                    Button {
                                        Haptics.light()
                                        searchText = tag
                                        performSearch(query: tag)
                                    } label: {
                                        Text(tag)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AuraTheme.textPrimary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .liquidGlass(cornerRadius: 20)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // Results or Status
                    if isSearching {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(AuraTheme.primary)
                            Text("Searching YouTube...")
                                .font(.system(size: 14))
                                .foregroundColor(AuraTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchResults.isEmpty {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 4) {
                                ForEach(searchResults) { result in
                                    let track = convertToMediaTrack(result)
                                    let isCur = (playback.currentTrack?.youtubeId == track.youtubeId)
                                    
                                    TrackRowView(
                                        track: track,
                                        isCurrent: isCur,
                                        isPlaying: playback.isPlaying,
                                        onTap: {
                                            playback.playTrack(track, inQueue: searchResults.map(convertToMediaTrack), context: .none)
                                        },
                                        onPlayVideo: {
                                            playback.displayMode = .video
                                            playback.playTrack(track, inQueue: searchResults.map(convertToMediaTrack), context: .none)
                                        },
                                        onAddToPlaylist: {
                                            trackForPlaylistSheet = track
                                        },
                                        onToggleFavorite: {
                                            playlistStore.toggleFavorite(track: track)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 120)
                        }
                    } else if suggestions.isEmpty && searchScope == .youtube {
                        youtubeFeed
                    } else if suggestions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(AuraTheme.textTertiary)
                            Text("Find Your Music")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AuraTheme.textPrimary)
                            Text("Search any track, artist, or music video.")
                                .font(.system(size: 14))
                                .foregroundColor(AuraTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $trackForPlaylistSheet) { t in
                AddToPlaylistSheet(track: t, playlistStore: playlistStore)
            }
        }
    }
    
    private func fetchSuggestions(for text: String) {
        guard searchResults.isEmpty else { return }
        // Wait for a pause in typing: one request per keystroke made typing lag
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let sugs = await YouTubeService.shared.getSuggestions(query: text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !self.searchText.isEmpty && self.searchResults.isEmpty {
                    self.suggestions = sugs
                } else {
                    self.suggestions = []
                }
            }
        }
    }
    
    // MARK: - YouTube topic feed
    
    private var feedTabs: [String] { ["Home"] + FavoriteChannels.topics }
    
    private var youtubeFeed: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(feedTabs, id: \.self) { tab in
                        Button {
                            Haptics.selection()
                            feedTab = tab
                            loadFeed(tab)
                        } label: {
                            VStack(spacing: 5) {
                                Text(tab)
                                    .font(.system(size: 16, weight: feedTab == tab ? .bold : .medium))
                                    .foregroundColor(feedTab == tab ? AuraTheme.textPrimary : AuraTheme.textSecondary)
                                Capsule()
                                    .fill(feedTab == tab ? AuraTheme.primary : Color.clear)
                                    .frame(height: 3)
                            }
                            .fixedSize()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 4)
            
            let items = feeds[feedTab] ?? []
            if items.isEmpty {
                VStack(spacing: 14) {
                    if feedLoading {
                        ProgressView().tint(AuraTheme.primary)
                        Text("Loading \(feedTab)...")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                    } else {
                        Text("Nothing loaded")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                        Button("Try again") { loadFeed(feedTab, force: true) }
                            .foregroundColor(AuraTheme.primary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { result in resultRow(result, queue: items) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 120)
                }
                .refreshable { await reloadFeed(feedTab) }
            }
        }
        .onAppear { loadFeed(feedTab) }
    }
    
    private func loadFeed(_ tab: String, force: Bool = false) {
        guard force || feeds[tab] == nil else { return }
        Task { await reloadFeed(tab) }
    }
    
    /// Latest videos from some of the channels under this tab, mixed together. A few random channels each time,
    /// since every channel is a separate page to download.
    private func reloadFeed(_ tab: String) async {
        await MainActor.run { feedLoading = true }
        let pool = tab == "Home" ? FavoriteChannels.all : FavoriteChannels.all.filter { $0.topic == tab }
        let picks = Array(pool.shuffled().prefix(tab == "Home" ? 12 : 8))
        
        var lists: [[YouTubeSearchResult]] = []
        await withTaskGroup(of: [YouTubeSearchResult].self) { group in
            for channel in picks {
                group.addTask { await YouTubeService.shared.channelVideos(handle: channel.handle, name: channel.name, limit: 4) }
            }
            for await list in group where !list.isEmpty { lists.append(list) }
        }
        
        // one from each channel in turn, so no channel fills the page
        var mixed: [YouTubeSearchResult] = []
        var seen = Set<String>()
        var round = 0
        while mixed.count < 40, lists.contains(where: { round < $0.count }) {
            for list in lists where round < list.count && seen.insert(list[round].id).inserted { mixed.append(list[round]) }
            round += 1
        }
        
        await MainActor.run {
            if !mixed.isEmpty { feeds[tab] = mixed }
            feedLoading = false
        }
    }
    
    private func resultRow(_ result: YouTubeSearchResult, queue items: [YouTubeSearchResult]) -> some View {
        let track = convertToMediaTrack(result)
        let queue = items.map(convertToMediaTrack)
        return TrackRowView(
            track: track,
            isCurrent: playback.currentTrack?.youtubeId == track.youtubeId,
            isPlaying: playback.isPlaying,
            onTap: { playback.playTrack(track, inQueue: queue, context: .none) },
            onPlayVideo: {
                playback.displayMode = .video
                playback.playTrack(track, inQueue: queue, context: .none)
            },
            onAddToPlaylist: { trackForPlaylistSheet = track },
            onToggleFavorite: { playlistStore.toggleFavorite(track: track) }
        )
    }
    
    private func scopeButton(_ scope: SearchScope) -> some View {
        let selected: Bool = (searchScope == scope)
        let textColor: Color = selected ? Color.white : AuraTheme.textSecondary
        return Button {
            Haptics.selection()
            searchScope = scope
            if !searchText.isEmpty {
                performSearch(query: searchText)
            } else {
                searchResults = []
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: scope.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(scope.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    AuraTheme.primaryGradient.clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Color.white.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    
    private func performSearch(query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        
        suggestions = []
        isSearching = true
        Task {
            let res: [YouTubeSearchResult]
            switch searchScope {
            case .music:
                // Official video song ranking with language awareness
                let lang = searchLanguage == "Any" ? nil : searchLanguage.lowercased()
                res = (try? await YouTubeService.shared.languageAwareSearch(
                    query: q, limit: 15, songTitle: nil, artist: nil, movie: nil, expectedDuration: nil, language: lang)) ?? []
            case .youtube:
                // Direct unfiltered YouTube search without studio music bias
                res = await YouTubeService.shared.search(query: q)
            }
            await MainActor.run {
                self.searchResults = res
                self.isSearching = false
            }
        }
    }
    
    private func convertToMediaTrack(_ result: YouTubeSearchResult) -> MediaTrack {
        let cleaned = MetadataCleaner.clean(title: result.title, artist: result.channel)
        return MediaTrack(
            title: cleaned.cleanTitle,
            artist: cleaned.primaryArtist,
            duration: result.duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: result.url,
            thumbnailURL: result.thumbnailURL,
            isFavorite: false,
            youtubeId: result.id
        )
    }
}
