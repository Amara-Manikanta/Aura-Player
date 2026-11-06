import SwiftUI
import AppKit

/// Music: songs ranked for you (language-aware). YouTube Direct: whatever YouTube lists, plus topic tabs.
private enum SearchScope: String, CaseIterable, Identifiable {
    case music = "Music"
    case youtube = "YouTube Direct"
    var id: String { rawValue }
}

public struct SearchView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    var onSelectPlaylist: ((UUID) -> Void)? = nil
    
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [YouTubeSearchResult] = []
    @State private var suggestions: [String] = []
    @State private var searchLanguage: String = "Any"
    @State private var statusMessage: String? = nil
    @State private var toastMessage: String? = nil
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var pendingDuplicate: PendingDuplicate?
    @State private var selectedPlaylistForAdd: UUID?
    @State private var searchScope: SearchScope = .music
    /// YouTube Direct before anything is typed: a feed per topic (Home, Tech, Music...), like YouTube's own tabs
    @State private var feedTab: String = "Home"
    @State private var feeds: [String: [YouTubeSearchResult]] = [:]
    @State private var feedLoading = false
    
    private static let languages = ["Any", "Telugu", "Hindi", "Tamil", "Kannada", "Malayalam", "English", "Punjabi"]
    private static let quickTags = ["Top Hits", "Telugu Hits", "Bollywood", "Lo-Fi Chill", "Tamil Hits", "Hindi Hits", "Ayyappa Swamy", "Sid Sriram", "A.R. Rahman", "Anirudh"]
    
    private struct PendingDuplicate {
        let track: MediaTrack
        let targetPlaylist: Playlist
        let existingPlaylists: [String]
        let playNow: Bool
    }
    
    public init(store: PlaylistStore, playback: PlaybackManager, onSelectPlaylist: ((UUID) -> Void)? = nil) {
        self.store = store
        self.playback = playback
        self.onSelectPlaylist = onSelectPlaylist
    }
    
    private var languageParam: String? {
        searchLanguage == "Any" ? nil : searchLanguage.lowercased()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Top Search Bar & Controls
            searchHeader
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)
                .background(.ultraThinMaterial)
            
            Divider()
            
            // Toast notification banner
            if let toast = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button {
                        toastMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.15))
                .overlay(Rectangle().stroke(Color.green.opacity(0.3), lineWidth: 1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: Main Content Area
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 20) {
                        if isSearching {
                            loadingView
                        } else if !searchResults.isEmpty {
                            resultsListView
                        } else if searchScope == .youtube {
                            youtubeFeedView
                        } else {
                            idleDiscoveryView
                        }
                    }
                    .padding(24)
                }
                
                // Live Autocomplete Suggestions Dropdown
                if !suggestions.isEmpty && searchResults.isEmpty && !isSearching {
                    suggestionsOverlay
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .zIndex(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "Song Already in Playlist",
            isPresented: Binding(
                get: { pendingDuplicate != nil },
                set: { if !$0 { pendingDuplicate = nil } }
            ),
            presenting: pendingDuplicate
        ) { dup in
            Button("Add Anyway") {
                store.addTrack(dup.track, to: dup.targetPlaylist.id, allowDuplicate: true)
                showToast("Added \"\(dup.track.title)\" to \(dup.targetPlaylist.name)")
                if dup.playNow {
                    playback.playTrack(dup.track, context: .none)
                }
            }
            if dup.playNow {
                Button("Just Play") {
                    playback.playTrack(dup.track, context: .none)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { dup in
            Text("\"\(dup.track.title)\" is already in: \(dup.existingPlaylists.joined(separator: ", ")). Do you want to add it to \"\(dup.targetPlaylist.name)\" anyway?")
        }
    }
    
    // MARK: - Search Header
    private var searchHeader: some View {
        VStack(spacing: 12) {
            Picker("", selection: $searchScope) {
                ForEach(SearchScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: searchScope) { _, _ in
                searchResults = []
                statusMessage = nil
                if !query.trimmingCharacters(in: .whitespaces).isEmpty { performSearch(query: query) }
            }
            
            HStack(spacing: 12) {
                // Search Input Field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.purple)
                    
                    TextField("Search YouTube for songs, artists, or paste YouTube link...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit {
                            suggestions = []
                            performSearch(query: query)
                        }
                        .onChange(of: query) { _, newQuery in
                            fetchSuggestions(for: newQuery)
                        }
                    
                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchResults = []
                            suggestions = []
                            statusMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                )
                
                // Language Filter Picker (the Music search only)
                if searchScope == .music {
                Picker("", selection: $searchLanguage) {
                    ForEach(Self.languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
                .onChange(of: searchLanguage) { _, _ in
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        performSearch(query: query)
                    }
                }
                .help("Select audio language filter")
                }
                
                // Search Action Button
                Button {
                    suggestions = []
                    performSearch(query: query)
                } label: {
                    HStack(spacing: 6) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Search")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            
            // Quick Filter Tag Pills (the Music search only)
            if searchScope == .music {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Popular:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)
                    
                    ForEach(Self.quickTags, id: \.self) { tag in
                        Button {
                            query = tag
                            suggestions = []
                            performSearch(query: tag)
                        } label: {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            }
        }
    }
    
    // MARK: - Autocomplete Suggestions
    private var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(6), id: \.self) { sug in
                Button {
                    query = sug
                    suggestions = []
                    performSearch(query: sug)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(sug)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.4)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.purple)
            Text("Searching YouTube for \"\(query)\"...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    // MARK: - Results List View
    private var resultsListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YouTube Results (\(searchResults.count))")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("Click + to add any song to your playlists")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            LazyVStack(spacing: 10) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                    searchResultRow(item: item, isBestMatch: index == 0)
                }
            }
        }
    }
    
    // MARK: - Single Search Result Row
    private func searchResultRow(item: YouTubeSearchResult, isBestMatch: Bool) -> some View {
        let track = convertToMediaTrack(item)
        let isCurrent = (playback.currentTrack?.youtubeId == track.youtubeId)
        let isFav = store.isFavorite(track: track)
        
        return HStack(spacing: 14) {
            // Thumbnail with duration overlay
            ZStack(alignment: .bottomTrailing) {
                if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.purple.opacity(0.2)
                        }
                    }
                    .frame(width: 84, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color.purple.opacity(0.4), Color.indigo.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 84, height: 52)
                        .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8)))
                }
                
                if !item.formattedDuration.isEmpty {
                    Text(item.formattedDuration)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            
            // Song Title & Artist / Channel
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isBestMatch {
                        Text("BEST MATCH")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.25))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                
                Text(item.channel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                // Play Audio
                Button {
                    playback.playTrack(track, context: .none)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(isCurrent && playback.isPlaying ? "Playing" : "Play")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isCurrent ? Color.purple.opacity(0.3) : Color.white.opacity(0.08))
                    .foregroundStyle(isCurrent ? Color.purple : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Play audio stream")
                
                // Play Video
                Button {
                    playback.displayMode = .video
                    playback.playTrack(track, context: .none)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Watch music video")
                
                // Add to Playlist Menu
                Menu {
                    Text("Add to Playlist:").font(.caption).disabled(true)
                    Divider()
                    ForEach(store.playlists) { pl in
                        Button {
                            addTrack(track, to: pl, playNow: false)
                        } label: {
                            Label(pl.name, systemImage: pl.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add to Playlist")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add this song to any playlist")
                
                // Favorite Toggle
                Button {
                    store.toggleFavorite(track: track)
                } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(isFav ? .red : .secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(isFav ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? Color.purple.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Idle / Discovery View
    private var idleDiscoveryView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.35), Color.indigo.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
            }
            
            VStack(spacing: 8) {
                Text("Search YouTube & Add to Library")
                    .font(.system(size: 20, weight: .bold))
                
                Text("Search for any song, artist, album, or video on YouTube.\nListen instantly without ads, or add new tracks to your playlists.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            
            if let err = statusMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            // Featured Genres Grid
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Search Categories")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    categoryCard(title: "Telugu Hits", icon: "music.note", color: .purple)
                    categoryCard(title: "Bollywood", icon: "sparkles", color: .pink)
                    categoryCard(title: "Top Global Hits", icon: "globe", color: .blue)
                    categoryCard(title: "Lo-Fi Beats", icon: "headphones", color: .teal)
                    categoryCard(title: "Tamil Hits", icon: "waveform", color: .orange)
                    categoryCard(title: "Devotional", icon: "sun.max.fill", color: .yellow)
                }
            }
            .frame(maxWidth: 580)
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    private func categoryCard(title: String, icon: String, color: Color) -> some View {
        Button {
            query = title
            performSearch(query: title)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - YouTube Direct topic feed
    private var feedTabs: [String] { ["Home"] + FavoriteChannels.topics }
    
    private var youtubeFeedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 26) {
                ForEach(feedTabs, id: \.self) { tab in
                    Button {
                        feedTab = tab
                        loadFeed(tab)
                    } label: {
                        VStack(spacing: 5) {
                            Text(tab)
                                .font(.system(size: 15, weight: feedTab == tab ? .bold : .medium))
                                .foregroundStyle(feedTab == tab ? Color.primary : Color.secondary)
                            Capsule()
                                .fill(feedTab == tab ? Color.red : Color.clear)
                                .frame(height: 3)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    loadFeed(feedTab, force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pick different channels")
            }
            
            let items = feeds[feedTab] ?? []
            if items.isEmpty {
                VStack(spacing: 12) {
                    if feedLoading {
                        ProgressView()
                        Text("Loading \(feedTab)...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nothing loaded")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Try again") { loadFeed(feedTab, force: true) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        searchResultRow(item: item, isBestMatch: false)
                    }
                }
            }
        }
        .onAppear { loadFeed(feedTab) }
    }
    
    private func loadFeed(_ tab: String, force: Bool = false) {
        guard force || feeds[tab] == nil else { return }
        feedLoading = true
        let pool = tab == "Home" ? FavoriteChannels.all : FavoriteChannels.all.filter { $0.topic == tab }
        // A few random channels each time: every channel is a separate page to download
        let picks = Array(pool.shuffled().prefix(tab == "Home" ? 12 : 8))
        Task {
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
    }
    
    // MARK: - Search & Suggestion Actions
    private func fetchSuggestions(for text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2, searchResults.isEmpty else {
            suggestions = []
            return
        }
        
        suggestionTask?.cancel()
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let sugs = await YouTubeService.shared.getSuggestions(query: clean)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !self.query.isEmpty && self.searchResults.isEmpty {
                    self.suggestions = sugs
                } else {
                    self.suggestions = []
                }
            }
        }
    }
    
    private func performSearch(query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        searchTask?.cancel()
        isSearching = true
        statusMessage = nil
        searchResults = []
        suggestions = []
        
        searchTask = Task {
            do {
                if searchScope == .youtube {
                    let results = await YouTubeService.shared.directSearch(query: clean)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                        if results.isEmpty { self.statusMessage = "No results found on YouTube for \"\(clean)\"" }
                    }
                } else if clean.contains("youtube.com") || clean.contains("youtu.be") {
                    let track = try await YouTubeService.shared.fetchTrackInfo(urlOrQuery: clean)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        let res = YouTubeSearchResult(
                            id: track.youtubeId ?? "",
                            title: track.title,
                            channel: track.artist,
                            duration: track.duration,
                            thumbnailURL: track.thumbnailURL,
                            url: track.originalURL.isEmpty ? clean : track.originalURL
                        )
                        self.searchResults = [res]
                        self.isSearching = false
                    }
                } else {
                    let results = try await YouTubeService.shared.languageAwareSearch(
                        query: clean,
                        limit: 12,
                        songTitle: nil,
                        artist: nil,
                        movie: nil,
                        expectedDuration: nil,
                        language: languageParam
                    )
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                        if results.isEmpty {
                            self.statusMessage = "No results found on YouTube for \"\(clean)\""
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSearching = false
                    self.statusMessage = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Add to Playlist Logic
    private func addTrack(_ track: MediaTrack, to playlist: Playlist, playNow: Bool) {
        let matches = store.playlistsContaining(track)
        if matches.contains(where: { $0.id == playlist.id }) {
            // Already in this specific playlist, prompt user
            pendingDuplicate = PendingDuplicate(
                track: track,
                targetPlaylist: playlist,
                existingPlaylists: matches.map { $0.name },
                playNow: playNow
            )
        } else {
            store.addTrack(track, to: playlist.id)
            showToast("Added \"\(track.title)\" to \(playlist.name)")
            if playNow {
                playback.playTrack(track, context: .none)
            }
        }
    }
    
    private func convertToMediaTrack(_ item: YouTubeSearchResult) -> MediaTrack {
        MediaTrack(
            title: item.title,
            artist: item.channel,
            duration: item.duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: item.url,
            thumbnailURL: item.thumbnailURL,
            youtubeId: item.id
        )
    }
    
    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = msg
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation {
                    if toastMessage == msg { toastMessage = nil }
                }
            }
        }
    }
}
