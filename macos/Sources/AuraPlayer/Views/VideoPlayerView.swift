import SwiftUI
import AVKit

public struct LocalVideoPlayerView: NSViewRepresentable {
    public let player: AVPlayer
    public var showsControls: Bool = true
    
    public init(player: AVPlayer, showsControls: Bool = true) {
        self.player = player
        self.showsControls = showsControls
    }
    
    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true
        playerView.showsSharingServiceButton = true
        playerView.controlsStyle = showsControls ? .floating : .none
        playerView.videoGravity = .resizeAspect
        return playerView
    }
    
    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.controlsStyle = showsControls ? .floating : .none
    }
}

public struct VideoPlayerView: View {
    public let track: MediaTrack
    @Bindable var playback: PlaybackManager
    
    @State private var resolvedVideoId: String?
    @State private var isLoadingVideoId: Bool = false
    @State private var showChangeVideoSheet: Bool = false
    
    public init(track: MediaTrack, playback: PlaybackManager) {
        self.track = track
        self.playback = playback
        self._resolvedVideoId = State(initialValue: track.youtubeId)
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if track.sourceType == .local {
                LocalVideoPlayerView(player: playback.player)
                    .ignoresSafeArea()
            } else {
                let activeVid = playback.currentTrack?.youtubeId ?? resolvedVideoId ?? track.youtubeId
                if playback.audioFallbackActive, let vid = activeVid {
                    VStack(spacing: 14) {
                        Image(systemName: "play.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("This video can't be shown here")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("The owner disabled embedding. The song's audio is playing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Watch on YouTube") {
                                if let url = URL(string: "https://www.youtube.com/watch?v=\(vid)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            Button("Choose a Different Video") {
                                showChangeVideoSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else if let vid = activeVid, !vid.isEmpty {
                    YouTubeWebPlayerView(videoId: vid, playback: playback)
                        .ignoresSafeArea()
                } else if isLoadingVideoId {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .colorInvert()
                        Text("Loading Official Music Video...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Video Unavailable")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        HStack(spacing: 10) {
                            Button("Retry Video") {
                                loadVideoId()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            
                            Button("Choose / Paste Link") {
                                showChangeVideoSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            // Top Controls Overlay
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showChangeVideoSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                            Text("Change Video")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Paste YouTube URL or Search Official Videos")
                    .padding(16)
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showChangeVideoSheet) {
            ChangeVideoLinkSheet(
                track: playback.currentTrack ?? track,
                store: playback.playlistStore ?? PlaylistStore(),
                playback: playback
            )
        }
        .onAppear {
            let activeVid = playback.currentTrack?.youtubeId ?? resolvedVideoId ?? track.youtubeId
            if (activeVid == nil || activeVid?.isEmpty == true) && track.sourceType == .youtube {
                loadVideoId()
            }
        }
        .onChange(of: track.id) { _, _ in
            let activeVid = playback.currentTrack?.youtubeId ?? track.youtubeId
            resolvedVideoId = activeVid
            if (activeVid == nil || activeVid?.isEmpty == true) && track.sourceType == .youtube {
                loadVideoId()
            }
        }
        .onChange(of: playback.currentTrack?.youtubeId) { _, newVid in
            if let newVid = newVid, !newVid.isEmpty {
                self.resolvedVideoId = newVid
            }
        }
    }
    
    private func loadVideoId() {
        if let existing = playback.currentTrack?.youtubeId, !existing.isEmpty {
            self.resolvedVideoId = existing
            return
        }
        isLoadingVideoId = true
        Task {
            let vid = await YouTubeService.shared.fastResolveVideoId(
                for: track.videoSearchQuery,
                songTitle: track.title,
                artist: track.artist,
                movie: track.movieName,
                expectedDuration: track.duration,
                language: playback.searchLanguage(for: track)
            )
            await MainActor.run {
                self.resolvedVideoId = vid
                self.playback.currentTrack?.youtubeId = vid
                self.isLoadingVideoId = false
            }
        }
    }
}
