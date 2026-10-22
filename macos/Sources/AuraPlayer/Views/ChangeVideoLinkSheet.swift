import SwiftUI

public struct ChangeVideoLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let track: MediaTrack
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    @State private var inputUrlOrId: String = ""
    @State private var searchQuery: String = ""
    @State private var searchResults: [YouTubeSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedVideoId: String?
    @State private var selectedThumbnailURL: String?
    @State private var previewTitle: String?
    @State private var errorMessage: String?
    
    public init(track: MediaTrack, store: PlaylistStore, playback: PlaybackManager) {
        self.track = track
        self.store = store
        self.playback = playback
        self._inputUrlOrId = State(initialValue: track.youtubeId.map { "https://www.youtube.com/watch?v=\($0)" } ?? "")
        self._selectedVideoId = State(initialValue: track.youtubeId)
        self._searchQuery = State(initialValue: "\(track.title) \(track.artist)")
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change Video Link")
                        .font(.title2.bold())
                    Text("\(track.title) • \(track.artist)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Option 1: Direct Link / ID
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Paste YouTube URL or Video ID", systemImage: "link")
                            .font(.headline)
                        
                        HStack(spacing: 10) {
                            TextField("e.g. https://www.youtube.com/watch?v=... or Video ID", text: $inputUrlOrId)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: inputUrlOrId) { _, newValue in
                                    resolveDirectInput(newValue)
                                }
                            
                            if let id = selectedVideoId, !id.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        if let id = selectedVideoId, !id.isEmpty {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 80, height: 45)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(previewTitle ?? "Video ID: \(id)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text("Ready to link to this track")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // Option 2: Search YouTube
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Search Official YouTube Videos", systemImage: "magnifyingglass")
                            .font(.headline)
                        
                        HStack(spacing: 10) {
                            TextField("Search song, movie, or artist...", text: $searchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    runSearch()
                                }
                            
                            Button {
                                runSearch()
                            } label: {
                                if isSearching {
                                    ProgressView().scaleEffect(0.7)
                                        .frame(width: 60)
                                } else {
                                    Text("Search")
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(isSearching || searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        
                        if !searchResults.isEmpty {
                            Text("Click any video below to select it:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 8) {
                                ForEach(searchResults) { result in
                                    HStack(spacing: 12) {
                                        if let thumb = result.thumbnailURL, let url = URL(string: thumb) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Color.gray.opacity(0.3)
                                                }
                                            }
                                            .frame(width: 80, height: 45)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.title)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(2)
                                            
                                            HStack(spacing: 8) {
                                                Text(result.channel)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text("•")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(result.formattedDuration)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedVideoId == result.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.purple)
                                                .font(.title3)
                                        } else {
                                            Button("Select") {
                                                selectedVideoId = result.id
                                                selectedThumbnailURL = result.thumbnailURL
                                                previewTitle = result.title
                                                inputUrlOrId = "https://www.youtube.com/watch?v=\(result.id)"
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(8)
                                    .background(selectedVideoId == result.id ? Color.purple.opacity(0.15) : Color.white.opacity(0.03))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedVideoId = result.id
                                        selectedThumbnailURL = result.thumbnailURL
                                        previewTitle = result.title
                                        inputUrlOrId = "https://www.youtube.com/watch?v=\(result.id)"
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                
                Spacer()
                
                Button("Apply Video Link") {
                    applySelectedVideo()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(selectedVideoId == nil || selectedVideoId?.isEmpty == true)
            }
            .padding(16)
        }
        .frame(width: 580, height: 600)
        .onAppear {
            if searchResults.isEmpty {
                runSearch()
            }
        }
    }
    
    private func resolveDirectInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectedVideoId = nil
            return
        }
        
        Task {
            let vid = await YouTubeService.shared.extractVideoId(from: trimmed)
            await MainActor.run {
                if let vid = vid {
                    self.selectedVideoId = vid
                    self.selectedThumbnailURL = "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"
                    self.errorMessage = nil
                } else if trimmed.count == 11 && !trimmed.contains("/") && !trimmed.contains(" ") {
                    self.selectedVideoId = trimmed
                    self.selectedThumbnailURL = "https://img.youtube.com/vi/\(trimmed)/hqdefault.jpg"
                    self.errorMessage = nil
                }
            }
        }
    }
    
    private func runSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                let results = try await YouTubeService.shared.searchVideos(query: searchQuery, limit: 8)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Search failed: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
    }
    
    private func applySelectedVideo() {
        guard let vid = selectedVideoId, !vid.isEmpty else { return }
        playback.setVideoIdForTrack(
            trackId: track.id,
            newVideoId: vid,
            newThumbnailURL: selectedThumbnailURL
        )
        dismiss()
    }
}
