import SwiftUI

public struct LibraryView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var showNewPlaylistDialog: Bool = false
    /// The playlist just made: opened straight away so it's clear it worked (new ones sit at the bottom of a long list)
    @State private var createdPlaylist: Playlist?
    @State private var newPlaylistTitle: String = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText: String = ""
    @State private var playlistToMerge: Playlist?
    @State private var showSettings: Bool = false
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Quick Library Shortcuts
                        VStack(spacing: 8) {
                            if let fav = playlistStore.favoritesPlaylist {
                                NavigationLink {
                                    PlaylistDetailView(playlist: fav, playlistStore: playlistStore, playback: playback)
                                } label: {
                                    LibraryShortcutRow(
                                        title: "Favorites",
                                        subtitle: "\(fav.tracks.count) tracks",
                                        icon: "heart.fill",
                                        iconColor: AuraTheme.primary
                                    )
                                }
                                .buttonStyle(AuraPlainButtonStyle())
                            }
                            
                            let mostPlayed = playlistStore.mostPlayedTracks
                            NavigationLink {
                                PlaylistDetailView(
                                    playlist: Playlist(name: "Most Played", iconName: "flame.fill", tracks: mostPlayed, isBuiltIn: true),
                                    playlistStore: playlistStore,
                                    playback: playback
                                )
                            } label: {
                                LibraryShortcutRow(
                                    title: "Most Played",
                                    subtitle: "\(mostPlayed.count) tracks",
                                    icon: "flame.fill",
                                    iconColor: Color.orange
                                )
                            }
                            .buttonStyle(AuraPlainButtonStyle())
                            
                            NavigationLink {
                                RecentlyAddedView(playlistStore: playlistStore, playback: playback)
                            } label: {
                                LibraryShortcutRow(
                                    title: "Recently Added",
                                    subtitle: "\(playlistStore.recentlyAddedTracks.count) tracks",
                                    icon: "clock.arrow.circlepath",
                                    iconColor: Color.teal
                                )
                            }
                            .buttonStyle(AuraPlainButtonStyle())
                            
                            NavigationLink {
                                NewReleasesView(playlistStore: playlistStore, playback: playback)
                            } label: {
                                LibraryShortcutRow(
                                    title: "New Releases",
                                    subtitle: "Latest YouTube music drops",
                                    icon: "sparkles.tv",
                                    iconColor: Color.purple
                                )
                            }
                            .buttonStyle(AuraPlainButtonStyle())
                            
                            NavigationLink {
                                ArtistsView(playlistStore: playlistStore, playback: playback)
                            } label: {
                                LibraryShortcutRow(
                                    title: "Singers & Artists",
                                    subtitle: "\(playlistStore.allArtists.count) artists",
                                    icon: "mic.fill",
                                    iconColor: Color(hex: 0x4E92DF)
                                )
                            }
                            .buttonStyle(AuraPlainButtonStyle())
                            
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        Divider().overlay(AuraTheme.glassBorder).padding(.horizontal, 16)
                        
                        // All Playlists Header
                        HStack {
                            Text("Playlists")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                            Spacer()
                            // Playlist or song shared from WhatsApp: copy the message, then tap this
                            Button {
                                Haptics.light()
                                if let text = UIPasteboard.general.string, !text.isEmpty {
                                    playlistStore.importShared(from: text)
                                } else {
                                    playlistStore.importNotice = "Copy the shared message from WhatsApp first, then tap Import."
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 22))
                                    .foregroundColor(AuraTheme.primary)
                            }
                            .padding(.trailing, 8)
                            Button {
                                showNewPlaylistDialog = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(AuraTheme.primary)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Custom Playlists List
                        LazyVStack(spacing: 6) {
                            ForEach(playlistStore.playlists.filter { !$0.isBuiltIn }) { pl in
                                NavigationLink {
                                    PlaylistDetailView(playlist: pl, playlistStore: playlistStore, playback: playback)
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(AuraTheme.surfaceElevated)
                                                .frame(width: 56, height: 56)
                                            
                                            if let thumb = pl.tracks.first?.thumbnailURL, let url = URL(string: thumb) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 56, height: 56)
                                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    } else {
                                                        Image(systemName: pl.iconName)
                                                            .foregroundColor(AuraTheme.primary)
                                                    }
                                                }
                                            } else {
                                                Image(systemName: pl.iconName)
                                                    .font(.system(size: 22))
                                                    .foregroundColor(AuraTheme.primary)
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pl.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(AuraTheme.textPrimary)
                                            Text("\(pl.tracks.count) tracks")
                                                .font(.system(size: 13))
                                                .foregroundColor(AuraTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .liquidGlass(cornerRadius: 14)
                                    .contextMenu {
                                        Button {
                                            if let first = pl.tracks.first {
                                                playback.playTrack(first, inQueue: pl.tracks, context: .playlist(pl.id))
                                            }
                                        } label: {
                                            Label("Play", systemImage: "play.fill")
                                        }
                                        
                                        Button {
                                            Haptics.light()
                                            let text = PlatformShareService.formatWhatsAppPlaylistShare(name: pl.name, tracks: pl.tracks)
                                            ShareSheet.present(text: text)
                                        } label: {
                                            Label("Share Playlist (WhatsApp / Link)", systemImage: "square.and.arrow.up")
                                        }
                                        
                                        Button {
                                            renameText = pl.name
                                            playlistToRename = pl
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        
                                        Button {
                                            playlistToMerge = pl
                                        } label: {
                                            Label("Merge with Another...", systemImage: "arrow.triangle.merge")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            playlistStore.deletePlaylist(id: pl.id)
                                        } label: {
                                            Label("Delete Playlist", systemImage: "trash")
                                        }
                                    }
                                }
                                .buttonStyle(AuraPlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        Spacer(minLength: 120)
                    }
                }
            }
            .navigationDestination(item: $createdPlaylist) { pl in
                PlaylistDetailView(playlist: pl, playlistStore: playlistStore, playback: playback)
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(playlistStore: playlistStore)
            }
            .alert("New Playlist", isPresented: $showNewPlaylistDialog) {
                TextField("Playlist name", text: $newPlaylistTitle)
                Button("Create") {
                    if !newPlaylistTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        createdPlaylist = playlistStore.createPlaylist(
                            name: newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                        Haptics.success()
                        newPlaylistTitle = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newPlaylistTitle = ""
                }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { playlistToRename != nil },
                set: { if !$0 { playlistToRename = nil } }
            )) {
                TextField("New name", text: $renameText)
                Button("Rename") {
                    if let target = playlistToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        playlistStore.renamePlaylist(id: target.id, newName: renameText)
                    }
                    playlistToRename = nil
                }
                Button("Cancel", role: .cancel) {
                    playlistToRename = nil
                }
            }
            .sheet(item: $playlistToMerge) { pl in
                MergePlaylistSheet(store: playlistStore, sourcePlaylist: pl)
            }
        }
    }
}

private struct LibraryShortcutRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AuraTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AuraTheme.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AuraTheme.textTertiary)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 14)
    }
}
