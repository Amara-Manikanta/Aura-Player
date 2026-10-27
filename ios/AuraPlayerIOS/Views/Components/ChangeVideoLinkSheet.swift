import SwiftUI
import UIKit

public struct ChangeVideoLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let track: MediaTrack
    @ObservedObject var store: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var inputUrlOrId: String = ""
    @State private var searchQuery: String = ""
    @State private var searchResults: [YouTubeSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedVideoId: String?
    @State private var selectedThumbnailURL: String?
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
        NavigationStack {
            ZStack {
                AuraBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Option 1: Direct Link / ID
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Paste YouTube URL or Video ID", systemImage: "link")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AuraTheme.textPrimary)
                            
                            HStack(spacing: 10) {
                                TextField("Paste a YouTube link or video ID", text: $inputUrlOrId)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(12)
                                    .padding(.trailing, inputUrlOrId.isEmpty ? 0 : 26)
                                    .overlay(alignment: .trailing) { clearButton($inputUrlOrId) }
                                    .liquidGlass(cornerRadius: 12)
                                    .foregroundColor(AuraTheme.textPrimary)
                                
                                // Paste a link copied from Discover / YouTube in one tap
                                if inputUrlOrId.isEmpty {
                                    Button {
                                        if let text = UIPasteboard.general.string { inputUrlOrId = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    } label: {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AuraTheme.primary)
                                            .frame(width: 40, height: 40)
                                            .liquidGlass(cornerRadius: 12)
                                    }
                                }
                                
                                Button("Apply") {
                                    applyDirectLink()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(AuraTheme.primary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        
                        Divider().overlay(AuraTheme.glassBorder)
                        
                        // Option 2: Search Alternative Videos
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Search Alternate Official Videos", systemImage: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AuraTheme.textPrimary)
                            
                            HStack(spacing: 10) {
                                TextField("Search query", text: $searchQuery)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .padding(.trailing, searchQuery.isEmpty ? 0 : 26)
                                    .overlay(alignment: .trailing) { clearButton($searchQuery) }
                                    .liquidGlass(cornerRadius: 12)
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .onSubmit { performSearch() }
                                
                                Button {
                                    performSearch()
                                } label: {
                                    if isSearching {
                                        ProgressView().tint(.white)
                                            .frame(width: 44, height: 44)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .liquidGlass(cornerRadius: 12)
                            }
                            
                            // Results
                            LazyVStack(spacing: 8) {
                                ForEach(searchResults) { result in
                                    let isSelected = (selectedVideoId == result.id)
                                    Button {
                                        Haptics.light()
                                        selectedVideoId = result.id
                                        selectedThumbnailURL = result.thumbnailURL
                                        inputUrlOrId = result.url
                                        applyVideo(id: result.id, thumb: result.thumbnailURL)
                                    } label: {
                                        HStack(spacing: 12) {
                                            if let thumb = result.thumbnailURL, let url = URL(string: thumb) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 60, height: 40)
                                                            .cornerRadius(8)
                                                    }
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.title)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(isSelected ? AuraTheme.primary : AuraTheme.textPrimary)
                                                    .lineLimit(1)
                                                Text(result.channel)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AuraTheme.textSecondary)
                                            }
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AuraTheme.primary)
                                            }
                                        }
                                        .padding(10)
                                        .background(isSelected ? AuraTheme.primary.opacity(0.15) : AuraTheme.surfaceCard)
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Change Video Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AuraTheme.primary)
                }
            }
            .onAppear {
                performSearch()
            }
        }
    }
    
    private func applyDirectLink() {
        let input = inputUrlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        var vid = input
        if let url = URL(string: input), let host = url.host?.lowercased() {
            if host.contains("youtube.com"), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                vid = items.first(where: { $0.name == "v" })?.value ?? input
            } else if host.contains("youtu.be") {
                vid = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        applyVideo(id: vid, thumb: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
    }
    
    private func applyVideo(id: String, thumb: String?) {
        // (used to edit the playlists without saving, so the new video was lost on restart)
        store.setVideo(trackId: track.id, videoId: id, thumbnailURL: thumb)
        if playback.currentTrack?.id == track.id {
            playback.currentTrack?.youtubeId = id
            playback.loadVideo(id: id)
        }
        Haptics.success()
        dismiss()
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            let res = await YouTubeService.shared.search(query: searchQuery)
            await MainActor.run {
                self.searchResults = res
                self.isSearching = false
            }
        }
    }
    
    /// ⓧ inside a text field: empties it
    @ViewBuilder
    private func clearButton(_ text: Binding<String>) -> some View {
        if !text.wrappedValue.isEmpty {
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AuraTheme.textTertiary)
                    .padding(.trailing, 10)
            }
            .buttonStyle(.plain)
        }
    }
}
