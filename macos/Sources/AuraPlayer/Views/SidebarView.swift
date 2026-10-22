import SwiftUI

public enum SidebarSelection: Hashable {
    case playlist(UUID)
    case nowPlaying
    case artists
    case mostPlayed
    case newReleases
    case forYou
    case recentlyAdded
}

public struct SidebarView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    @Binding var selection: SidebarSelection?
    @Binding var showAddTrackSheet: Bool
    @Binding var showAppleMusicSheet: Bool
    @Binding var showVideoView: Bool
    
    @State private var showNewPlaylistAlert: Bool = false
    @State private var newPlaylistName: String = ""
    
    // Rename state
    @State private var showRenameAlert: Bool = false
    @State private var playlistToRename: Playlist?
    @State private var renameText: String = ""
    
    // Merge state
    @State private var playlistToMerge: Playlist?
    
    // Song details refresh
    @State private var isUpdatingDetails: Bool = false
    @State private var detailsResultMessage: String?
    
    public init(
        store: PlaylistStore,
        playback: PlaybackManager,
        selection: Binding<SidebarSelection?>,
        showAddTrackSheet: Binding<Bool>,
        showAppleMusicSheet: Binding<Bool>,
        showVideoView: Binding<Bool>
    ) {
        self.store = store
        self.playback = playback
        self._selection = selection
        self._showAddTrackSheet = showAddTrackSheet
        self._showAppleMusicSheet = showAppleMusicSheet
        self._showVideoView = showVideoView
    }
    
    public var body: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: SidebarSelection.nowPlaying) {
                    Label {
                        HStack {
                            Text("Now Playing")
                            Spacer()
                            if playback.isPlaying {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.purple)
                                    .symbolEffect(.variableColor.iterative.reversing)
                            }
                        }
                    } icon: {
                        Image(systemName: "music.note")
                            .foregroundStyle(.purple)
                    }
                }
                
                if let fav = store.favoritesPlaylist {
                    NavigationLink(value: SidebarSelection.playlist(fav.id)) {
                        Label {
                            HStack {
                                Text("Favorites")
                                Spacer()
                                Text("\(fav.tracks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                NavigationLink(value: SidebarSelection.forYou) {
                    Label {
                        Text("Discover")
                    } icon: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.pink)
                    }
                }
                
                NavigationLink(value: SidebarSelection.recentlyAdded) {
                    Label {
                        Text("Recently Added")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.teal)
                    }
                }
                
                NavigationLink(value: SidebarSelection.mostPlayed) {
                    Label {
                        HStack {
                            Text("Most Played")
                            Spacer()
                            Text("\(store.mostPlayedTracks.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                
                NavigationLink(value: SidebarSelection.artists) {
                    Label {
                        HStack {
                            Text("Singers & Artists")
                            Spacer()
                            Text("\(store.allArtists.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.mic")
                            .foregroundStyle(.indigo)
                    }
                }
                
                if let local = store.localLibraryPlaylist {
                    NavigationLink(value: SidebarSelection.playlist(local.id)) {
                        Label {
                            HStack {
                                Text("Local Media")
                                Spacer()
                                Text("\(local.tracks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            
            Section("Playlists") {
                ForEach(store.playlists.filter { !$0.isBuiltIn }) { pl in
                    NavigationLink(value: SidebarSelection.playlist(pl.id)) {
                        Label {
                            HStack {
                                Text(pl.name)
                                Spacer()
                                Text("\(pl.tracks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: pl.iconName)
                                .foregroundStyle(.purple)
                        }
                    }
                    .contextMenu {
                        Button {
                            if let first = pl.tracks.first {
                                playback.playTrack(first, inQueue: pl.tracks, context: .playlist(pl.id))
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                        
                        Divider()
                        
                        Button {
                            playlistToRename = pl
                            renameText = pl.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename Playlist...", systemImage: "pencil")
                        }
                        
                        Button {
                            playlistToMerge = pl
                        } label: {
                            Label("Merge with Playlist...", systemImage: "arrow.triangle.merge")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            if selection == .playlist(pl.id) {
                                let remaining = store.playlists.first(where: { $0.id != pl.id && !$0.isBuiltIn }) ?? store.playlists.first
                                if let nextId = remaining?.id {
                                    selection = .playlist(nextId)
                                } else {
                                    selection = .nowPlaying
                                }
                            }
                            store.deletePlaylist(id: pl.id)
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                }
                
                Button {
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Label("New Playlist...", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Section("Apple Music") {
                Button {
                    showAppleMusicSheet = true
                } label: {
                    Label {
                        HStack {
                            Text("Import Library...")
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "apple.logo")
                            .foregroundStyle(.pink)
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    updateSongDetails()
                } label: {
                    Label {
                        HStack {
                            Text(isUpdatingDetails ? "Updating Details..." : "Update Song Details")
                            Spacer()
                            if isUpdatingDetails {
                                ProgressView().controlSize(.small)
                            }
                        }
                    } icon: {
                        Image(systemName: "text.badge.checkmark")
                            .foregroundStyle(.pink)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingDetails)
                .help("Fill in movie/album, composer and year from Apple Music so songs find the right video")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                showAddTrackSheet = true
            } label: {
                Label("Add Songs / Videos", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.addPlaylist(name: newPlaylistName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("New Playlist Name", text: $renameText)
            Button("Rename") {
                if let target = playlistToRename {
                    store.renamePlaylist(id: target.id, newName: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $playlistToMerge) { target in
            MergePlaylistSheet(
                store: store,
                sourcePlaylist: target,
                onMerged: { newId in
                    selection = .playlist(newId)
                }
            )
        }
        .onChange(of: selection) { _, _ in
            showVideoView = false
        }
        .alert(
            "Song Details",
            isPresented: Binding(get: { detailsResultMessage != nil }, set: { if !$0 { detailsResultMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(detailsResultMessage ?? "")
        }
    }
    
    private func updateSongDetails() {
        isUpdatingDetails = true
        Task {
            do {
                let details = try await AppleMusicService.shared.fetchLibraryDetails()
                let updated = store.applySongDetails(details)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAppleMusicSync")
                let total = store.playlists.reduce(0) { $0 + $1.tracks.count }
                let withMovie = store.playlists.reduce(0) { $0 + $1.tracks.filter { $0.movieName != nil }.count }
                detailsResultMessage = "Updated \(updated) songs. \(withMovie) of \(total) songs now have a movie/album name for searching."
            } catch {
                detailsResultMessage = "Couldn't read Apple Music: \(error.localizedDescription)"
            }
            isUpdatingDetails = false
        }
    }
}
