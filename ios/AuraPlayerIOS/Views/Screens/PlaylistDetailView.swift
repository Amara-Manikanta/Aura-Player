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
    @State private var showAddSongs: Bool = false
    @State private var searchText: String = ""
    
    public init(playlist: Playlist, playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlist = playlist
        self.playlistStore = playlistStore
        self.playback = playback
        _renameText = State(initialValue: playlist.name)
    }
    
    /// A real saved playlist (Most Played / Recently Added are generated lists you can't add to)
    private var canAddSongs: Bool {
        playlistStore.playlists.contains { $0.id == playlist.id }
    }
    
    private var currentPlaylist: Playlist {
        playlistStore.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }
    
    /// Songs matching the search: title, singer, album or movie; every word must match, and
    /// spelling variants count ("Chinnadana" finds "Chinnadhana")
    private var visibleTracks: [MediaTrack] {
        TrackSearchIndex.filter(currentPlaylist.tracks, query: searchText)
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
                    
                    // Action Buttons
                    if !currentPlaylist.tracks.isEmpty {
                        VStack(spacing: 12) {
                            // Primary Playback Row: Play All & Shuffle
                            HStack(spacing: 14) {
                                Button {
                                    Haptics.medium()
                                    if let first = currentPlaylist.tracks.first {
                                        playback.playTrack(first, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        Text("Play All")
                                            .font(.system(size: 16, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(AuraTheme.primaryGradient)
                                    .cornerRadius(25)
                                    .shadow(color: AuraTheme.primary.opacity(0.3), radius: 10, y: 4)
                                }
                                
                                Button {
                                    Haptics.medium()
                                    guard !currentPlaylist.tracks.isEmpty else { return }
                                    playback.isShuffled = true
                                    var pool = currentPlaylist.tracks
                                    if pool.count > 1, let current = playback.currentTrack {
                                        pool.removeAll { $0.id == current.id }
                                    }
                                    pool.shuffle()
                                    let pick = pool.first ?? currentPlaylist.tracks.first!
                                    var fullQueue = currentPlaylist.tracks.filter { $0.id != pick.id }.shuffled()
                                    fullQueue.insert(pick, at: 0)
                                    playback.playTrack(pick, inQueue: fullQueue, context: .playlist(currentPlaylist.id))
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 16, weight: .bold))
                                        Text("Shuffle")
                                            .font(.system(size: 16, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .liquidGlass(cornerRadius: 25)
                                }
                            }
                            
                            // Secondary Actions Row: Add Songs & Share
                            HStack(spacing: 12) {
                                if canAddSongs {
                                    Button {
                                        Haptics.light()
                                        showAddSongs = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 15, weight: .semibold))
                                            Text("Add Songs")
                                                .font(.system(size: 14, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(AuraTheme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .liquidGlass(cornerRadius: 21)
                                    }
                                    .accessibilityLabel("Add songs")
                                }

                                Button {
                                    Haptics.light()
                                    sharePlaylist()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(canAddSongs ? "Share" : "Share Playlist")
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .liquidGlass(cornerRadius: 21)
                                }
                                .accessibilityLabel("Share playlist")
                            }
                        }
                        .padding(.horizontal, 20)
                    } else if canAddSongs {
                        // Empty playlist: invite the first song
                        Button {
                            Haptics.light()
                            showAddSongs = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Songs")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AuraTheme.primaryGradient)
                            .cornerRadius(25)
                        }
                        .padding(.horizontal, 24)
                        Text("Add songs by name or by pasting a YouTube link")
                            .font(.system(size: 13))
                            .foregroundColor(AuraTheme.textSecondary)
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
        .sheet(isPresented: $showAddSongs) {
            AddSongsSheet(playlistId: currentPlaylist.id, playlistStore: playlistStore)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canAddSongs {
                        Button {
                            showAddSongs = true
                        } label: {
                            Label("Add Songs", systemImage: "plus")
                        }
                    }
                    if !currentPlaylist.tracks.isEmpty {
                        Button {
                            if let first = currentPlaylist.tracks.first {
                                playback.playTrack(first, inQueue: currentPlaylist.tracks, context: .playlist(currentPlaylist.id))
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }

                        Button {
                            sharePlaylist()
                        } label: {
                            Label("Share Playlist", systemImage: "square.and.arrow.up")
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
                        .font(.system(size: 20))
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
    
    private func sharePlaylist() {
        let text = PlatformShareService.formatWhatsAppPlaylistShare(name: currentPlaylist.name, tracks: currentPlaylist.tracks)
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}
