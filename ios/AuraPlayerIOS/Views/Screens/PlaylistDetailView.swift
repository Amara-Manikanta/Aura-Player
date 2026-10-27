import SwiftUI

public struct PlaylistDetailView: View {
    public let playlist: Playlist
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var trackForPlaylistSheet: MediaTrack?
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showDeleteAlert: Bool = false
    @State private var showMergeSheet: Bool = false
    @State private var searchText: String = ""
    
    public init(playlist: Playlist, playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlist = playlist
        self.playlistStore = playlistStore
        self.playback = playback
        _renameText = State(initialValue: playlist.name)
    }
    
    private var currentPlaylist: Playlist {
        playlistStore.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }
    
    /// Songs matching the search: title, singer, album or movie; every word must match, and
    /// spelling variants count ("Chinnadana" finds "Chinnadhana")
    private var visibleTracks: [MediaTrack] {
        let words = searchText.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return currentPlaylist.tracks }
        return currentPlaylist.tracks.filter { t in
            let text = [t.title, t.artist, t.album ?? "", t.movieName ?? ""].joined(separator: " ")
            let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            let loose = YouTubeService.translit(text)
            return words.allSatisfy { w in plain.contains(w) || loose.contains(YouTubeService.translit(w)) }
        }
    }
    
    public var body: some View {
        ZStack {
            AuraBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Banner
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(AuraTheme.surfaceElevated)
                                .frame(width: 160, height: 160)
                                .shadow(color: AuraTheme.primary.opacity(0.2), radius: 20)
                            
                            if let firstThumb = currentPlaylist.tracks.first?.effectiveThumbnailURL,
                               let url = URL(string: firstThumb) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 160, height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 24))
                                    } else {
                                        Image(systemName: currentPlaylist.iconName)
                                            .font(.system(size: 64))
                                            .foregroundColor(AuraTheme.primary)
                                    }
                                }
                            } else {
                                Image(systemName: currentPlaylist.iconName)
                                    .font(.system(size: 64))
                                    .foregroundColor(AuraTheme.primary)
                            }
                        }
                        
                        Text(currentPlaylist.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AuraTheme.textPrimary)
                        
                        Text("\(currentPlaylist.tracks.count) Songs")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                    .padding(.top, 16)
                    
                    // Action Buttons (Play All & Shuffle)
                    if !currentPlaylist.tracks.isEmpty {
                        HStack(spacing: 16) {
                            Button {
                                Haptics.medium()
                                if let first = currentPlaylist.tracks.first {
                                    playback.playTrack(first, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play All")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(AuraTheme.primaryGradient)
                                .cornerRadius(25)
                                .shadow(color: AuraTheme.primary.opacity(0.3), radius: 10, y: 4)
                            }
                            
                            Button {
                                Haptics.medium()
                                playback.isShuffled = true
                                let shuffled = currentPlaylist.tracks.shuffled()
                                if let first = shuffled.first {
                                    playback.playTrack(first, inQueue: shuffled, context: .playlist(currentPlaylist.id))
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "shuffle")
                                    Text("Shuffle")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .liquidGlass(cornerRadius: 25)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Search in this playlist
                    if currentPlaylist.tracks.count > 1 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(AuraTheme.textTertiary)
                            TextField("Search in \(currentPlaylist.name.trimmingCharacters(in: .whitespaces))", text: $searchText)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                                .foregroundColor(AuraTheme.textPrimary)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, 16)
                        
                        if !searchText.isEmpty {
                            Text(visibleTracks.isEmpty ? "No songs match \"\(searchText)\"" : "\(visibleTracks.count) of \(currentPlaylist.tracks.count) songs")
                                .font(.system(size: 12))
                                .foregroundColor(AuraTheme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // Track list
                    LazyVStack(spacing: 4) {
                        ForEach(visibleTracks) { track in
                            let isCur = (playback.currentTrack?.id == track.id)
                            TrackRowView(
                                track: track,
                                isCurrent: isCur,
                                isPlaying: playback.isPlaying,
                                onTap: {
                                    playback.playTrack(track, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                                },
                                onPlayVideo: {
                                    playback.displayMode = .video
                                    playback.playTrack(track, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                                },
                                onAddToPlaylist: {
                                    trackForPlaylistSheet = track
                                },
                                onToggleFavorite: {
                                    playlistStore.toggleFavorite(track: track)
                                },
                                onRemove: {
                                    playlistStore.removeTrack(trackId: track.id, from: currentPlaylist.id)
                                },
                                playlistId: currentPlaylist.id
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 120) // Spacing for floating mini player
                }
            }
        }
        // Scrolling the results closes the keyboard, so the whole list is visible
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(currentPlaylist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !currentPlaylist.tracks.isEmpty {
                        Button {
                            if let first = currentPlaylist.tracks.first {
                                playback.playTrack(first, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                    }
                    
                    if !currentPlaylist.isBuiltIn {
                        Button {
                            renameText = currentPlaylist.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename Playlist", systemImage: "pencil")
                        }
                        
                        Button {
                            showMergeSheet = true
                        } label: {
                            Label("Merge with Another...", systemImage: "arrow.triangle.merge")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(AuraTheme.primary)
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Playlist Name", text: $renameText)
            Button("Save") {
                playlistStore.renamePlaylist(id: currentPlaylist.id, newName: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Playlist", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                playlistStore.deletePlaylist(id: currentPlaylist.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(currentPlaylist.name)\"? This cannot be undone.")
        }
        .sheet(isPresented: $showMergeSheet) {
            MergePlaylistSheet(store: playlistStore, sourcePlaylist: currentPlaylist)
        }
        .sheet(item: $trackForPlaylistSheet) { t in
            AddToPlaylistSheet(track: t, playlistStore: playlistStore)
        }
    }
}
