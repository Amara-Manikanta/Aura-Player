import SwiftUI

public enum SearchScope: String, CaseIterable, Identifiable {
    case music = "Music"
    case youtube = "YouTube Direct"
    case devotional = "Devotional"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .music: return "music.note"
        case .youtube: return "play.rectangle.fill"
        case .devotional: return "sparkles"
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
                    
                    // Search Scope Selector (Music / YouTube Direct / Devotional)
                    HStack(spacing: 6) {
                        ForEach(SearchScope.allCases) { scope in
                            scopeButton(scope)
                        }
                    }
                    .padding(4)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 16)
                    
                    // Language of the version to find (re-runs the search)
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
                    if searchResults.isEmpty && !isSearching && suggestions.isEmpty {
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
    
    private func scopeButton(_ scope: SearchScope) -> some View {
        let selected: Bool = (searchScope == scope)
        let textColor: Color = selected ? Color.white : AuraTheme.textSecondary
        return Button {
            Haptics.selection()
            searchScope = scope
            if !searchText.isEmpty {
                performSearch(query: searchText)
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
            case .devotional:
                // Devotional mode: preserve audio jukeboxes, stotrams, keertanas, mantras & bhajans
                let lower = q.lowercased()
                let devKeywords = ["devotional", "bhajan", "stotram", "stuti", "keertana", "kirtan", "aarti", "chalisa", "mantra", "suprabhatam", "ayyappa", "shiva", "venkateswara", "ram", "krishna", "durga", "hanuman", "song"]
                let hasDevWord = devKeywords.contains { lower.contains($0) }
                let devQuery = hasDevWord ? q : "\(q) devotional songs"
                res = await YouTubeService.shared.search(query: devQuery)
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
