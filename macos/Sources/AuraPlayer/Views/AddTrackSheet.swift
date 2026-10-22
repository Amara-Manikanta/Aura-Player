import SwiftUI
import AppKit
import AVFoundation

public struct AddTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    var targetPlaylistId: UUID
    
    @State private var selectedTab: Int = 0
    @State private var youtubeQuery: String = ""
    @State private var isFetching: Bool = false
    @State private var fetchedTrack: MediaTrack?
    @State private var searchResults: [YouTubeSearchResult] = []
    @State private var errorMessage: String?
    @State private var destinationPlaylistId: UUID
    /// Language version to search for ("Any" = no preference); starts from the playlist's language
    @State private var searchLanguage: String = "Any"
    private static let searchLanguages = ["Any", "Telugu", "Hindi", "Tamil", "Kannada", "Malayalam", "Marathi", "Punjabi"]
    @State private var appleMusicPlaylists: [AppleMusicPlaylistInfo] = []
    @State private var isLoadingAppleMusic: Bool = false
    @State private var isImportingFromAppleMusic: Bool = false
    @State private var pendingDuplicate: PendingDuplicate?
    @State private var searchTask: Task<Void, Never>?
    
    /// A song the user tried to add that already exists in one or more playlists.
    private struct PendingDuplicate {
        let track: MediaTrack
        let playNow: Bool
        let playlistNames: [String]
        let inDestination: Bool
        /// Saved songs this video is a video of, when they use a different video
        let existingSongs: [MediaTrack]
    }
    
    public init(store: PlaylistStore, playback: PlaybackManager, targetPlaylistId: UUID) {
        self.store = store
        self.playback = playback
        self.targetPlaylistId = targetPlaylistId
        self._destinationPlaylistId = State(initialValue: targetPlaylistId)
        self._searchLanguage = State(initialValue: Self.language(forPlaylistNamed: store.playlists.first { $0.id == targetPlaylistId }?.name))
    }
    
    /// "Hindi Music" → "Hindi"; playlists without a language in their name → "Any"
    private static func language(forPlaylistNamed name: String?) -> String {
        guard let name, let lang = PlaybackManager.playlistLanguage(name), !lang.isEmpty else { return "Any" }
        return lang.prefix(1).uppercased() + lang.dropFirst()
    }
    
    private var languageParam: String? {
        searchLanguage == "Any" ? nil : searchLanguage.lowercased()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Music & Videos")
                    .font(.title3.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("YouTube Stream").tag(0)
                Text("Local Files").tag(1)
                Text("Apple Music").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            Divider()
            
            if selectedTab == 0 {
                youtubeTab
            } else if selectedTab == 1 {
                localFilesTab
            } else {
                appleMusicTab
            }
            
            Divider()
            
            // Footer with playlist selector
            HStack {
                Text("Add to:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $destinationPlaylistId) {
                    ForEach(store.playlists) { pl in
                        Label(pl.name, systemImage: pl.iconName).tag(pl.id)
                    }
                }
                .frame(width: 180)
                .onChange(of: destinationPlaylistId) { _, newId in
                    let lang = Self.language(forPlaylistNamed: store.playlists.first { $0.id == newId }?.name)
                    if lang != "Any" { searchLanguage = lang }
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 480)
        .alert(
            "Song Already Added",
            isPresented: Binding(
                get: { pendingDuplicate != nil },
                set: { if !$0 { pendingDuplicate = nil } }
            ),
            presenting: pendingDuplicate
        ) { dup in
            if let existing = dup.existingSongs.first, let videoId = dup.track.youtubeId {
                Button("Save This Link to \"\(existing.coreTitle)\"") {
                    store.setVideo(forSongsLike: existing, videoId: videoId, thumbnailURL: dup.track.thumbnailURL)
                    AppLog.log("feedback", "saved video \(videoId) to existing song \"\(existing.title)\"")
                    if dup.playNow, let updated = store.savedSongs(matching: dup.track).first?.track {
                        playback.playTrack(updated, context: .none)
                    }
                    dismiss()
                }
            }
            Button(dup.inDestination ? "Add Again" : "Add Anyway") {
                store.addTrack(dup.track, to: destinationPlaylistId, allowDuplicate: true)
                if dup.playNow { playback.playTrack(dup.track, context: .none) }
                dismiss()
            }
            if dup.playNow {
                Button("Just Play") {
                    playback.playTrack(dup.track, context: .none)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { dup in
            if let existing = dup.existingSongs.first {
                Text("This looks like \"\(existing.title)\" by \(existing.artist), already in: \(dup.playlistNames.joined(separator: ", ")). You can save this link as that song's video instead of adding it again.")
            } else {
                Text("\"\(dup.track.title)\" is already in: \(dup.playlistNames.joined(separator: ", ")).")
            }
        }
    }
    
    // MARK: - YouTube Tab
    private var youtubeTab: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("Paste YouTube URL or type song name...", text: $youtubeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        searchOrFetch()
                    }
                    .onChange(of: youtubeQuery) { _, _ in
                        scheduleSearchAsYouType()
                    }
                
                Picker("", selection: $searchLanguage) {
                    ForEach(Self.searchLanguages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                .help("Find the version of the song in this language")
                .onChange(of: searchLanguage) { _, _ in
                    if !youtubeQuery.trimmingCharacters(in: .whitespaces).isEmpty && !Self.isYouTubeLink(youtubeQuery) {
                        searchOrFetch()
                    }
                }
                
                Button {
                    searchOrFetch()
                } label: {
                    if isFetching {
                        ProgressView().scaleEffect(0.6).frame(width: 50)
                    } else {
                        Text("Search / Load")
                    }
                }
                .disabled(youtubeQuery.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
                
                if !Self.isYouTubeLink(youtubeQuery) {
                    Button {
                        playBestMatch()
                    } label: {
                        Label("Play Best Match", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(youtubeQuery.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
                    .help("Find the official video song and play it")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            // Results list or preview card
            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 12) {
                                if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Color.gray.opacity(0.3)
                                        }
                                    }
                                    .frame(width: 60, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if index == 0 {
                                            Text("BEST MATCH")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.25))
                                                .foregroundStyle(.purple)
                                                .clipShape(Capsule())
                                        }
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    Text("\(item.channel) • \(item.formattedDuration)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    addCheckingDuplicates(track(from: item), playNow: true)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .controlSize(.small)
                                .help("Add and play")
                                
                                Button("Add") {
                                    addSearchResult(item)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }
            } else if let track = fetchedTrack {
                VStack(spacing: 12) {
                    if let thumb = track.thumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: 140, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text("\(track.artist) • \(track.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button("Add to Playlist") {
                            addCheckingDuplicates(track, playNow: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        
                        Button("Play Now") {
                            addCheckingDuplicates(track, playNow: true)
                        }
                    }
                }
                .padding()
                Spacer()
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 44))
                        .foregroundStyle(.purple.opacity(0.7))
                    Text("Ad-Free YouTube Music & Video")
                        .font(.headline)
                    Text("Paste any YouTube link, playlist, or search keywords to stream directly in pristine quality without ads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Local Files Tab
    private var localFilesTab: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            
            VStack(spacing: 6) {
                Text("Import Local Songs & Videos")
                    .font(.headline)
                Text("Supports MP3, M4A, FLAC, WAV, AAC, MP4, MOV, MKV files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("Choose Files from Mac...") {
                openLocalFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Apple Music Tab
    private var appleMusicTab: some View {
        VStack(spacing: 12) {
            if isLoadingAppleMusic {
                Spacer()
                ProgressView()
                Text("Reading Apple Music Playlists...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if appleMusicPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "apple.logo")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    Text("Apple Music Playlists")
                        .font(.headline)
                    Button("Scan Playlists") {
                        loadAppleMusic()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    Spacer()
                }
            } else {
                List(appleMusicPlaylists) { pl in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(pl.trackCount) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import") {
                            importAppleMusicPlaylist(pl)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .controlSize(.small)
                        .disabled(isImportingFromAppleMusic)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if appleMusicPlaylists.isEmpty {
                loadAppleMusic()
            }
        }
    }
    
    private func loadAppleMusic() {
        isLoadingAppleMusic = true
        Task {
            do {
                let fetched = try await AppleMusicService.shared.fetchUserPlaylists()
                await MainActor.run {
                    self.appleMusicPlaylists = fetched
                    self.isLoadingAppleMusic = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingAppleMusic = false
                }
            }
        }
    }
    
    private func importAppleMusicPlaylist(_ pl: AppleMusicPlaylistInfo) {
        isImportingFromAppleMusic = true
        Task {
            do {
                let tracks = try await AppleMusicService.shared.fetchTracks(forPlaylist: pl.name, maxCount: 200)
                await MainActor.run {
                    for t in tracks {
                        store.addTrack(t, to: destinationPlaylistId)
                    }
                    self.isImportingFromAppleMusic = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isImportingFromAppleMusic = false
                }
            }
        }
    }
    
    private static func isYouTubeLink(_ q: String) -> Bool {
        q.contains("youtube.com") || q.contains("youtu.be")
    }
    
    /// Searches shortly after the user stops typing (links still load on Enter / button).
    private func scheduleSearchAsYouType() {
        searchTask?.cancel()
        isFetching = false
        let q = youtubeQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, !Self.isYouTubeLink(q) else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            searchOrFetch()
        }
    }
    
    private func searchOrFetch() {
        let q = youtubeQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        
        searchTask?.cancel()
        isFetching = true
        errorMessage = nil
        fetchedTrack = nil
        searchResults = []
        
        searchTask = Task {
            do {
                if Self.isYouTubeLink(q) {
                    let track = try await YouTubeService.shared.fetchTrackInfo(urlOrQuery: q)
                    guard !Task.isCancelled else { return }
                    self.fetchedTrack = track
                } else {
                    let results = try await YouTubeService.shared.languageAwareSearch(query: q, limit: 6, songTitle: nil, artist: nil, movie: nil, expectedDuration: nil, language: languageParam)
                    // Ignore results for a query the user has since changed
                    guard !Task.isCancelled else { return }
                    self.searchResults = results
                    if results.isEmpty {
                        self.errorMessage = "No results found for \"\(q)\""
                    }
                }
                self.isFetching = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Could not load: \(error.localizedDescription)"
                self.isFetching = false
            }
        }
    }
    
    private func track(from item: YouTubeSearchResult) -> MediaTrack {
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
    
    private func addSearchResult(_ item: YouTubeSearchResult) {
        addCheckingDuplicates(track(from: item), playNow: false)
    }
    
    /// Searches for the typed song and immediately adds + plays the top-ranked official video.
    private func playBestMatch() {
        let q = youtubeQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        
        searchTask?.cancel()
        isFetching = true
        errorMessage = nil
        fetchedTrack = nil
        
        searchTask = Task {
            do {
                let results = try await YouTubeService.shared.languageAwareSearch(query: q, limit: 6, songTitle: nil, artist: nil, movie: nil, expectedDuration: nil, language: languageParam)
                guard !Task.isCancelled else { return }
                self.searchResults = results
                self.isFetching = false
                if let best = results.first {
                    addCheckingDuplicates(track(from: best), playNow: true)
                } else {
                    self.errorMessage = "No official video found for \"\(q)\""
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Could not load: \(error.localizedDescription)"
                self.isFetching = false
            }
        }
    }
    
    /// Adds the track, or asks first if the same song is already in any playlist.
    private func addCheckingDuplicates(_ track: MediaTrack, playNow: Bool) {
        let matches = store.playlistsContaining(track)
        guard !matches.isEmpty else {
            store.addTrack(track, to: destinationPlaylistId)
            if playNow { playback.playTrack(track, context: .none) }
            dismiss()
            return
        }
        pendingDuplicate = PendingDuplicate(
            track: track,
            playNow: playNow,
            playlistNames: matches.map { $0.name.trimmingCharacters(in: .whitespaces) },
            inDestination: matches.contains { $0.id == destinationPlaylistId },
            existingSongs: store.savedSongs(matching: track)
                .map(\.track)
                .filter { $0.youtubeId != track.youtubeId }
        )
    }
    
    private func openLocalFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .audio,
            .mpeg4Movie,
            .quickTimeMovie,
            .movie
        ]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                let asset = AVURLAsset(url: url)
                let duration = CMTimeGetSeconds(asset.duration)
                let fileName = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                let isVideo = ["mp4", "mov", "mkv", "m4v"].contains(ext)
                
                let track = MediaTrack(
                    title: fileName,
                    artist: "Local Media",
                    duration: duration.isNaN ? 0 : duration,
                    sourceType: .local,
                    mediaType: isVideo ? .video : .audio,
                    originalURL: url.path
                )
                
                store.addTrack(track, to: destinationPlaylistId)
            }
            dismiss()
        }
    }
}
