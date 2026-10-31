import SwiftUI
import UIKit

/// Add songs straight into one playlist: type a song name (pick the right video from the results,
/// or add it by name only) or paste a YouTube link.
public struct AddSongsSheet: View {
    let playlistId: UUID
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var text: String = ""
    @State private var results: [YouTubeSearchResult] = []
    @State private var isSearching = false
    @State private var searchedFor = ""
    @State private var notFound = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    @AppStorage("searchLanguage") private var searchLanguage: String = "Any"
    @FocusState private var focused: Bool
    
    public init(playlistId: UUID, playlistStore: PlaylistStore) {
        self.playlistId = playlistId
        self.playlistStore = playlistStore
    }
    
    private var playlist: Playlist? { playlistStore.playlists.first { $0.id == playlistId } }
    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isLink: Bool { YouTubeService.shared.extractVideoId(from: typed) != nil && (typed.contains("/") || typed.contains(".") || typed.count == 11) }
    
    /// The playlist's own language ("Telugu Music" → Telugu), else the Search tab's language choice
    private var language: String? {
        if let name = playlist?.name, let lang = PlaybackManager.playlistLanguage(name) { return lang.isEmpty ? nil : lang }
        return searchLanguage == "Any" ? nil : searchLanguage.lowercased()
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                VStack(spacing: 10) {
                    inputField
                    
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            if !typed.isEmpty && !isLink {
                                byNameRow
                            }
                            if isSearching {
                                ProgressView().tint(AuraTheme.primary).padding(.top, 30)
                            } else if notFound {
                                Text(isLink ? "Couldn't read that link. Check it and try again." : "No official video found for \"\(searchedFor)\".")
                                    .font(.system(size: 13))
                                    .foregroundColor(AuraTheme.textSecondary)
                                    .padding(.top, 24)
                            }
                            ForEach(results) { result in
                                resultRow(result)
                            }
                            if results.isEmpty && !isSearching && !notFound && typed.isEmpty {
                                hint
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                
                if let message {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.bottom, 30)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Add to \((playlist?.name ?? "Playlist").trimmingCharacters(in: .whitespaces))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AuraTheme.primary)
                }
            }
            .onAppear { focused = true }
        }
    }
    
    // MARK: - Pieces
    
    private var inputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(AuraTheme.textTertiary)
            TextField("Song name or YouTube link", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(AuraTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { startSearch() }
                .onChange(of: text) { _ in
                    // Typing again clears the old results
                    if !results.isEmpty || notFound { results = []; notFound = false }
                }
            if text.isEmpty {
                // Apple's own paste button: no "allow paste" prompt
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty else { return }
                    text = pasted
                    startSearch()
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(AuraTheme.primary)
            } else {
                Button {
                    text = ""
                    results = []
                    notFound = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(AuraTheme.textTertiary)
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(AuraTheme.textTertiary)
            Text("Type a song name, or paste a YouTube link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AuraTheme.textPrimary)
            Text("Pick the right video from the results, or add just the name and the official video is found when you play it.")
                .font(.system(size: 13))
                .foregroundColor(AuraTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 50)
        .padding(.horizontal, 20)
    }
    
    /// "Add 'Naatu Naatu' by name": no video picked; it's looked up when played (like importing from Apple Music)
    private var byNameRow: some View {
        Button {
            addByName()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AuraTheme.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \"\(typed)\" by name")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AuraTheme.textPrimary)
                        .lineLimit(1)
                    Text("The official video is found when you play it")
                        .font(.system(size: 12))
                        .foregroundColor(AuraTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AuraTheme.primary)
            }
            .padding(10)
            .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
    
    private func resultRow(_ result: YouTubeSearchResult) -> some View {
        let added = isInPlaylist(result)
        return Button {
            add(result)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: result.thumbnailURL ?? "")) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.12)
                    }
                }
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AuraTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(result.channel + (result.duration > 0 ? " • \(result.formattedDuration)" : ""))
                        .font(.system(size: 12))
                        .foregroundColor(AuraTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(added ? Color.green : AuraTheme.primary)
            }
            .padding(8)
            .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func startSearch() {
        let query = typed
        guard !query.isEmpty else { return }
        focused = false
        searchTask?.cancel()
        results = []
        notFound = false
        isSearching = true
        searchedFor = query
        let lang = language
        searchTask = Task {
            var found: [YouTubeSearchResult] = []
            if let id = YouTubeService.shared.extractVideoId(from: query), query.contains("/") || query.contains(".") || query.count == 11 {
                // A link: show that exact video, with its real title and length
                if let detail = await YouTubeService.shared.linkDetails(videoId: id) { found = [detail] }
            } else {
                // Same ranking as the Mac app: official video song first; lyric videos, Shorts, covers dropped
                found = (try? await YouTubeService.shared.languageAwareSearch(
                    query: query, limit: 15, songTitle: nil, artist: nil, movie: nil, expectedDuration: nil, language: lang)) ?? []
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = found
                notFound = found.isEmpty
                isSearching = false
            }
        }
    }
    
    private func track(from result: YouTubeSearchResult) -> MediaTrack {
        let cleaned = MetadataCleaner.clean(title: result.title, artist: result.channel)
        return MediaTrack(
            title: cleaned.cleanTitle,
            artist: cleaned.primaryArtist,
            duration: result.duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: result.url,
            thumbnailURL: result.thumbnailURL,
            youtubeId: result.id
        )
    }
    
    private func isInPlaylist(_ result: YouTubeSearchResult) -> Bool {
        guard let tracks = playlist?.tracks else { return false }
        if tracks.contains(where: { $0.youtubeId == result.id }) { return true }
        let candidate = track(from: result)
        return tracks.contains { PlaylistStore.isSameSong($0, candidate) }
    }
    
    private func add(_ result: YouTubeSearchResult) {
        guard let playlist else { return }
        let name = playlist.name.trimmingCharacters(in: .whitespaces)
        if isInPlaylist(result) {
            show("Already in \(name)")
            return
        }
        playlistStore.addTrack(track(from: result), to: playlistId)
        Haptics.success()
        show("Added to \(name)")
    }
    
    private func addByName() {
        guard let playlist else { return }
        let name = playlist.name.trimmingCharacters(in: .whitespaces)
        // Same shape as songs imported from Apple Music: the name is the "link", found when played
        let song = MediaTrack(title: typed, artist: "Unknown Artist", sourceType: .youtube, mediaType: .video, originalURL: typed)
        if playlist.tracks.contains(where: { PlaylistStore.isSameSong($0, song) }) {
            show("\"\(typed)\" is already in \(name)")
            return
        }
        playlistStore.addTrack(song, to: playlistId)
        Haptics.success()
        show("Added \"\(typed)\" to \(name)")
        text = ""
    }
    
    private func show(_ text: String) {
        withAnimation { message = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { withAnimation { if message == text { message = nil } } }
        }
    }
}
