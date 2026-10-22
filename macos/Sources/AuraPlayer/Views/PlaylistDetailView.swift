import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

public struct PlaylistDetailView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    let playlistId: UUID
    @Binding var showAddTrackSheet: Bool
    var onSelectPlaylist: ((UUID) -> Void)? = nil
    
    @State private var searchText: String = ""
    @State private var isTargetedForDrop: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var playlistToMerge: Playlist? = nil
    @State private var trackToChangeVideo: MediaTrack? = nil
    @State private var trackToTrim: MediaTrack? = nil
    @State private var transferMessage: String? = nil
    
    public init(
        store: PlaylistStore,
        playback: PlaybackManager,
        playlistId: UUID,
        showAddTrackSheet: Binding<Bool>,
        onSelectPlaylist: ((UUID) -> Void)? = nil
    ) {
        self.store = store
        self.playback = playback
        self.playlistId = playlistId
        self._showAddTrackSheet = showAddTrackSheet
        self.onSelectPlaylist = onSelectPlaylist
    }
    
    private var playlist: Playlist? {
        store.playlists.first { $0.id == playlistId }
    }
    
    private var filteredTracks: [MediaTrack] {
        guard let pl = playlist else { return [] }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return pl.tracks
        }
        return pl.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var totalDurationString: String {
        guard let pl = playlist else { return "" }
        let total = pl.tracks.reduce(0) { $0 + $1.duration }
        let mins = Int(total) / 60
        if mins > 60 {
            let hours = mins / 60
            let remMins = mins % 60
            return "\(hours) hr \(remMins) min"
        } else {
            return "\(mins) min"
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let pl = playlist {
                // Header
                HStack(spacing: 20) {
                    // Artwork / Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: pl.iconName)
                            .font(.system(size: 38))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pl.isBuiltIn ? "PLAYLIST" : "CUSTOM PLAYLIST")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        Text(pl.name)
                            .font(.system(size: 26, weight: .bold))
                        
                        HStack(spacing: 6) {
                            Text("\(pl.tracks.count) tracks")
                            if !totalDurationString.isEmpty {
                                Text("•")
                                Text(totalDurationString)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Header Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            if let first = pl.tracks.first {
                                playback.playTrack(first, inQueue: pl.tracks, context: .playlist(pl.id))
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(pl.tracks.isEmpty)
                        
                        Button {
                            var shuffled = pl.tracks
                            shuffled.shuffle()
                            if let first = shuffled.first {
                                playback.playTrack(first, inQueue: shuffled, context: .playlist(pl.id))
                            }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(pl.tracks.isEmpty)
                        
                        Button {
                            showAddTrackSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .padding(8)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help("Add Songs or Videos")
                        
                        Menu {
                            Button("Rename Playlist...") {
                                renameText = pl.name
                                showRenameAlert = true
                            }
                            Button("Merge with Another Playlist...") {
                                playlistToMerge = playlist
                            }
                            if !pl.isBuiltIn {
                                Divider()
                                Button(role: .destructive) {
                                    let remaining = store.playlists.first(where: { $0.id != pl.id && !$0.isBuiltIn }) ?? store.playlists.first
                                    store.deletePlaylist(id: pl.id)
                                    if let nextId = remaining?.id {
                                        onSelectPlaylist?(nextId)
                                    }
                                } label: {
                                    Label("Delete Playlist", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Playlist Actions")
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter songs in playlist...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                
                // Track List
                if pl.tracks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Tracks Yet")
                            .font(.headline)
                        Text("Add YouTube songs or drag & drop local audio/video files here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button("Add Tracks Now") {
                            showAddTrackSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .padding(.top, 8)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(
                                index: index + 1,
                                track: track,
                                isCurrent: playback.currentTrack?.id == track.id,
                                isPlaying: playback.isPlaying && playback.currentTrack?.id == track.id,
                                onPlay: {
                                    playback.playTrack(track, inQueue: pl.tracks, context: .playlist(pl.id))
                                },
                                onToggleFavorite: {
                                    store.toggleFavorite(track: track)
                                },
                                onChangeVideo: {
                                    trackToChangeVideo = track
                                },
                                onSetTrim: {
                                    trackToTrim = track
                                },
                                otherPlaylists: store.playlists.filter { $0.id != pl.id },
                                onMove: { destination in
                                    let result = store.moveTrack(track.id, from: pl.id, to: destination)
                                    transferMessage = Self.transferText(result, track: track, destination: store.playlists.first { $0.id == destination }?.name)
                                },
                                onCopy: { destination in
                                    let result = store.copyTrack(track.id, from: pl.id, to: destination)
                                    transferMessage = Self.transferText(result, track: track, destination: store.playlists.first { $0.id == destination }?.name)
                                },
                                onRemove: {
                                    store.removeTrack(trackId: track.id, from: pl.id)
                                }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                Text("Playlist not found")
                    .foregroundStyle(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple, lineWidth: 3)
                    .background(Color.purple.opacity(0.1))
                    .overlay(
                        Text("Drop files to add to playlist")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    )
            }
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("New Playlist Name", text: $renameText)
            Button("Rename") {
                if let pl = playlist {
                    store.renamePlaylist(id: pl.id, newName: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $playlistToMerge) { pl in
            MergePlaylistSheet(
                store: store,
                sourcePlaylist: pl,
                onMerged: { newId in
                    onSelectPlaylist?(newId)
                }
            )
        }
        .alert("Playlists", isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transferMessage ?? "")
        }
        .sheet(item: $trackToTrim) { tr in
            TrimTimesSheet(track: tr, store: store, playback: playback)
        }
        .sheet(item: $trackToChangeVideo) { tr in
            ChangeVideoLinkSheet(track: tr, store: store, playback: playback)
        }
    }
    
    static func transferText(_ result: PlaylistStore.TransferResult, track: MediaTrack, destination: String?) -> String? {
        let dest = (destination ?? "the playlist").trimmingCharacters(in: .whitespaces)
        switch result {
        case .moved: return nil   // the song simply leaves this list
        case .copied: return "\"\(track.title)\" was added to \(dest)."
        case .alreadyThere: return "\"\(track.title)\" is already in \(dest)."
        case .notFound: return "Couldn't find that song."
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
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
                
                Task { @MainActor in
                    store.addTrack(track, to: playlistId)
                }
            }
        }
    }
}

public struct TrackRowView: View {
    public let index: Int
    public let track: MediaTrack
    public let isCurrent: Bool
    public let isPlaying: Bool
    public let onPlay: () -> Void
    public let onToggleFavorite: () -> Void
    public let onChangeVideo: () -> Void
    public var onSetTrim: () -> Void = {}
    /// Other playlists a song can be moved or copied to
    public var otherPlaylists: [Playlist] = []
    public var onMove: (UUID) -> Void = { _ in }
    public var onCopy: (UUID) -> Void = { _ in }
    public let onRemove: () -> Void
    
    @State private var isHovered: Bool = false
    
    public var body: some View {
        HStack(spacing: 12) {
            // Index or Play Indicator
            ZStack {
                if isCurrent {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.purple)
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                } else {
                    Text("\(index)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)
            
            // Album cover
            TrackArtworkView(track: track, size: 44, cornerRadius: 6)
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Color.purple : Color.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let trim = track.trimLabel {
                        Label(trim, systemImage: "scissors")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple)
                            .help("Plays only this part of the song")
                    }
                    if track.totalPlays > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 9))
                            Text("\(track.totalPlays) plays")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if track.sourceType == .youtube {
                        Text("YouTube")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.8)))
                    } else {
                        Text("Local")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.8)))
                    }
                }
            }
            
            Spacer()
            
            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            
            // Favorite Toggle
            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(track.isFavorite ? .red : .secondary.opacity(isHovered ? 1.0 : 0.0))
            }
            .buttonStyle(.plain)
            
            // Options Menu
            Menu {
                Button("Play Next") {
                    onPlay()
                }
                Button {
                    onChangeVideo()
                } label: {
                    Label("Change Video Link...", systemImage: "link.badge.plus")
                }
                Button {
                    onSetTrim()
                } label: {
                    Label("Set Start & End Time...", systemImage: "scissors")
                }
                if !otherPlaylists.isEmpty {
                    Menu {
                        ForEach(otherPlaylists) { pl in
                            Button(pl.name.trimmingCharacters(in: .whitespaces)) { onMove(pl.id) }
                        }
                    } label: {
                        Label("Move to Playlist", systemImage: "arrow.right.circle")
                    }
                    Menu {
                        ForEach(otherPlaylists) { pl in
                            Button(pl.name.trimmingCharacters(in: .whitespaces)) { onCopy(pl.id) }
                        }
                    } label: {
                        Label("Add to Another Playlist", systemImage: "plus.circle")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Playlist", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(isHovered ? 1.0 : 0.0))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            onPlay()
        }
        .contextMenu {
            Button("Play") {
                onPlay()
            }
            Button {
                onChangeVideo()
            } label: {
                Label("Change Video Link...", systemImage: "link.badge.plus")
            }
            Button {
                onToggleFavorite()
            } label: {
                Label(track.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: track.isFavorite ? "heart.slash" : "heart")
            }
            if !otherPlaylists.isEmpty {
                Menu {
                    ForEach(otherPlaylists) { pl in
                        Button(pl.name.trimmingCharacters(in: .whitespaces)) { onMove(pl.id) }
                    }
                } label: {
                    Label("Move to Playlist", systemImage: "arrow.right.circle")
                }
                Menu {
                    ForEach(otherPlaylists) { pl in
                        Button(pl.name.trimmingCharacters(in: .whitespaces)) { onCopy(pl.id) }
                    }
                } label: {
                    Label("Add to Another Playlist", systemImage: "plus.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Playlist", systemImage: "trash")
            }
        }
    }
}
