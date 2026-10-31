import SwiftUI
import AppKit

public struct MainView: View {
    @State private var store = PlaylistStore()
    @State private var playback = PlaybackManager.shared
    @State private var selection: SidebarSelection? = .nowPlaying
    @State private var showVideoView: Bool = false
    @State private var showAddTrackSheet: Bool = false
    @State private var showAppleMusicSheet: Bool = false
    @State private var selectedArtist: String? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                playback: playback,
                selection: $selection,
                showAddTrackSheet: $showAddTrackSheet,
                showAppleMusicSheet: $showAppleMusicSheet,
                showVideoView: $showVideoView
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                
                let isVideoActive = (showVideoView || playback.displayMode == .video) && (selection == .nowPlaying || selection == nil)
                
                // Standard Views (Music Cover Art, Lyrics, Playlists, Library)
                Group {
                    switch selection {
                    case .nowPlaying:
                        AudioPlayerView(playback: playback)
                    case .playlist(let id):
                        PlaylistDetailView(
                            store: store,
                            playback: playback,
                            playlistId: id,
                            showAddTrackSheet: $showAddTrackSheet,
                            onSelectPlaylist: { newId in
                                selection = .playlist(newId)
                            }
                        )
                    case .recentlyAdded:
                        RecentlyAddedView(store: store, playback: playback)
                    case .forYou, .newReleases:
                        DiscoverView(store: store, playback: playback)
                    case .mostPlayed:
                        MostPlayedView(
                            store: store,
                            playback: playback
                        )
                    case .artists:
                        if let artist = selectedArtist {
                            ArtistDetailView(
                                store: store,
                                playback: playback,
                                artistName: artist,
                                onBack: {
                                    selectedArtist = nil
                                }
                            )
                        } else {
                            ArtistsView(
                                store: store,
                                playback: playback,
                                selectedArtist: $selectedArtist
                            )
                        }
                    case .none:
                        AudioPlayerView(playback: playback)
                    }
                }
                .opacity(isVideoActive ? 0 : 1)
                .allowsHitTesting(!isVideoActive)
                
                // Video Player Area (Persistent for YouTube and video tracks so playback and time updates NEVER stop)
                if let current = playback.currentTrack, (current.sourceType == .youtube || current.mediaType == .video) {
                    ZStack {
                        if isVideoActive {
                            Color.black.ignoresSafeArea()
                        }
                        
                        if playback.videoInMiniPlayer && isVideoActive {
                            VStack(spacing: 12) {
                                Image(systemName: "pip")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.secondary)
                                Text("Playing in Mini Player")
                                    .font(.headline)
                                Text("Switch the mini player to Music, or close it, to watch here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VideoPlayerView(track: current, playback: playback)
                                .ignoresSafeArea()
                        }
                    }
                    .frame(
                        width: isVideoActive ? nil : 1,
                        height: isVideoActive ? nil : 1
                    )
                    .opacity(isVideoActive ? 1 : 0.001)
                    .allowsHitTesting(isVideoActive)
                    .accessibilityHidden(!isVideoActive)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomControlBar(
                    playback: playback,
                    store: store,
                    showVideoView: $showVideoView,
                    selection: $selection
                )
            }
        }
        .sheet(isPresented: $showAddTrackSheet) {
            AddTrackSheet(
                store: store,
                playback: playback,
                targetPlaylistId: currentSelectedPlaylistId
            )
        }
        .sheet(isPresented: $showAppleMusicSheet) {
            AppleMusicImportSheet(
                store: store,
                playback: playback
            )
        }
        .task {
            // Let the iPhone app sync with this library over Wi-Fi
            SyncServer.shared.start(store: store)
        }
        .task {
            await store.autoSyncAppleMusic()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.autoSyncAppleMusic() }
        }
        .onAppear {
            playback.playlistStore = store
            if selection == nil {
                selection = .nowPlaying
            }
        }
        .onChange(of: selection) { _, newSel in
            if newSel != .artists {
                selectedArtist = nil
            }
            if newSel != .nowPlaying {
                showVideoView = false
            }
        }
        .onChange(of: playback.videoInMiniPlayer) { _, inMini in
            // Mini player gave the video back: resume it here only if this window is in Video view
            if !inMini { playback.setVideoViewActive(showVideoView) }
        }
        .onChange(of: showVideoView) { _, isVideo in
            if isVideo {
                selection = .nowPlaying
                playback.displayMode = .video
            } else if playback.displayMode == .video {
                playback.displayMode = .audio
            }
        }
        .onChange(of: playback.displayMode) { _, newMode in
            showVideoView = (newMode == .video)
        }
    }
    
    private var currentSelectedPlaylistId: UUID {
        if case .playlist(let id) = selection {
            return id
        }
        return store.favoritesPlaylistId
    }
}
