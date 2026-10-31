import SwiftUI

public struct LibraryView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var showNewPlaylistDialog: Bool = false
    @State private var backupURL: URL?
    /// The playlist just made: opened straight away so it's clear it worked (new ones sit at the bottom of a long list)
    @State private var createdPlaylist: Playlist?
    @State private var newPlaylistTitle: String = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText: String = ""
    @State private var playlistToMerge: Playlist?
    @State private var showFileImporter: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var showSettings: Bool = false
    @State private var statusToast: String?
    
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
                                .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
                            
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
                            .buttonStyle(.plain)
                            
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
                            .buttonStyle(.plain)
                            
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
                            .buttonStyle(.plain)
                            
                            Button {
                                showSettings = true
                            } label: {
                                LibraryShortcutRow(
                                    title: "Settings & Themes",
                                    subtitle: "Switch between Modern Glass and Sansa e260 Retro",
                                    icon: "gearshape.fill",
                                    iconColor: Color(hex: 0x00D4FF)
                                )
                            }
                            .buttonStyle(.plain)
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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        Divider().overlay(AuraTheme.glassBorder).padding(.horizontal, 16).padding(.top, 10)
                        
                        // Data & Backup Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Data & Backup")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 8) {
                                // 1. Share / Export Backup
                                if let backupURL {
                                    ShareLink(
                                        item: backupURL,
                                        preview: SharePreview("AuraPlayer Library Backup", icon: Image(systemName: "arrow.down.doc.fill"))
                                    ) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(AuraTheme.primary)
                                                .frame(width: 32, height: 32)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Export Library Backup")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(AuraTheme.textPrimary)
                                                Text("Save playlists to Files, iCloud Drive, or AirDrop")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AuraTheme.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(AuraTheme.textTertiary)
                                        }
                                        .padding(12)
                                        .liquidGlass(cornerRadius: 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // 2. Import Backup from Files
                                Button {
                                    showFileImporter = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.teal)
                                            .frame(width: 32, height: 32)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Import Backup from Files")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AuraTheme.textPrimary)
                                            Text("Restore playlists from any .json backup")
                                                .font(.system(size: 12))
                                                .foregroundColor(AuraTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(12)
                                    .liquidGlass(cornerRadius: 12)
                                }
                                .buttonStyle(.plain)
                                
                                // 3. Reset to Bundled macOS Library
                                Button {
                                    showResetConfirmation = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "arrow.counterclockwise.circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.orange)
                                            .frame(width: 32, height: 32)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Restore Bundled Library")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AuraTheme.textPrimary)
                                            Text("Reload all 17 playlists and 3,432 original tracks")
                                                .font(.system(size: 12))
                                                .foregroundColor(AuraTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(12)
                                    .liquidGlass(cornerRadius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        if let toast = statusToast {
                            Text(toast)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AuraTheme.primary)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                        }
                        
                        Spacer(minLength: 120)
                    }
                }
            }
            .navigationDestination(item: $createdPlaylist) { pl in
                PlaylistDetailView(playlist: pl, playlistStore: playlistStore, playback: playback)
            }
            // The backup file is made once, off the main thread (it used to be rebuilt on every redraw)
            .task { backupURL = await playlistStore.createBackupFile() }
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        let ok = playlistStore.importBackup(from: first)
                        statusToast = ok ? "Library restored successfully!" : "Failed to parse backup JSON."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                    }
                case .failure(let err):
                    statusToast = "Error picking file: \(err.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                }
            }
            .confirmationDialog(
                "Restore Bundled Library?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore All 3,432 Original Tracks", role: .destructive) {
                    playlistStore.resetToBundled()
                    statusToast = "Restored all 17 playlists and 3,432 tracks!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reload the initial macOS library with all 17 playlists and 3,432 tracks from the embedded bundle.")
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
