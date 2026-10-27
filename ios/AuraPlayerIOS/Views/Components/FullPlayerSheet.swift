import SwiftUI

public struct FullPlayerSheet: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("playerTheme") private var playerTheme: PlayerTheme = .modern
    @State private var showSettings: Bool = false
    
    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showAddToPlaylist: Bool = false
    @State private var showChangeVideo: Bool = false
    @State private var showTrimTimes: Bool = false
    @State private var showFullScreenVideo: Bool = false
    
    public init(playback: PlaybackManager, playlistStore: PlaylistStore) {
        self.playback = playback
        self.playlistStore = playlistStore
    }
    
    private var currentProgress: Double {
        if isDraggingSlider { return sliderValue }
        guard playback.duration > 0 else { return 0 }
        return (playback.currentTime / playback.duration).clamped(to: 0...1)
    }
    
    private var artworkDimension: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // Adapt gracefully between small and large iPhones
        if screenHeight < 700 {
            return min(screenWidth - 80, 220)
        } else if screenHeight < 800 {
            return min(screenWidth - 70, 260)
        } else {
            return min(screenWidth - 64, 300)
        }
    }
    
    public var body: some View {
        guard let track = playback.currentTrack else { return AnyView(EmptyView()) }
        
        return AnyView(
            ZStack {
                if playerTheme == .sansa {
                    SansaPlayerView(
                        playback: playback,
                        playlistStore: playlistStore,
                        onDismiss: { dismiss() },
                        onOpenSettings: { showSettings = true }
                    )
                } else {
                    // Violet glass backdrop
                    AuraBackground()
                    
                    VStack(spacing: 0) {
                        // Top Bar (Collapse Chevron, Mode Selector Pill, Menu)
                        HStack {
                            Button {
                                Haptics.light()
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AuraTheme.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                            
                            Spacer()
                            
                            // Audio / Video / Lyrics Segmented Pill
                            HStack(spacing: 2) {
                                ForEach(PlaybackDisplayMode.allCases, id: \.self) { mode in
                                    Button {
                                        Haptics.light()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            playback.displayMode = mode
                                        }
                                    } label: {
                                        Text(mode.rawValue)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(playback.displayMode == mode ? .white : AuraTheme.textTertiary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                playback.displayMode == mode ? AuraTheme.primary : Color.clear
                                            )
                                            .cornerRadius(14)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                            }
                            .padding(3)
                            .background(AuraTheme.surfaceElevated.opacity(0.95))
                            .cornerRadius(17)
                            
                            Spacer()
                            
                            Menu {
                                Button {
                                    showAddToPlaylist = true
                                } label: {
                                    Label("Add to Playlist", systemImage: "text.badge.plus")
                                }
                                
                                Button {
                                    showChangeVideo = true
                                } label: {
                                    Label("Change Video Link", systemImage: "link")
                                }
                                
                                Section("Start & End Time") {
                                    Button {
                                        let now = playback.currentTime
                                        let end = (track.endTime ?? 0) > now + 1 ? track.endTime : nil
                                        playlistStore.setTrimTimes(for: track, start: now, end: end)
                                        playback.currentTrack?.startTime = now
                                        playback.currentTrack?.endTime = end
                                    } label: {
                                        Label("Start From Current Position", systemImage: "arrow.right.to.line")
                                    }
                                    Button {
                                        let now = playback.currentTime
                                        let start = (track.startTime ?? 0) < now - 1 ? track.startTime : nil
                                        playlistStore.setTrimTimes(for: track, start: start, end: now)
                                        playback.currentTrack?.startTime = start
                                        playback.currentTrack?.endTime = now
                                    } label: {
                                        Label("End at Current Position", systemImage: "arrow.left.to.line")
                                    }
                                    Button {
                                        showTrimTimes = true
                                    } label: {
                                        Label("Set Start & End Time…", systemImage: "scissors")
                                    }
                                    if track.startTime != nil || track.endTime != nil {
                                        Button(role: .destructive) {
                                            playlistStore.setTrimTimes(for: track, start: nil, end: nil)
                                            playback.currentTrack?.startTime = nil
                                            playback.currentTrack?.endTime = nil
                                        } label: {
                                            Label("Clear Start & End Time", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                                
                                Button {
                                    playlistStore.toggleFavorite(track: track)
                                } label: {
                                    Label(playlistStore.isTrackFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
                                          systemImage: playlistStore.isTrackFavorite(track) ? "heart.slash" : "heart")
                                }
                                
                                Divider()
                                
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        playerTheme = (playerTheme == .modern ? .sansa : .modern)
                                    }
                                } label: {
                                    Label(
                                        playerTheme == .modern ? "Switch to Sansa e260 Theme" : "Switch to Modern Glass",
                                        systemImage: playerTheme == .modern ? "opticaldisc.fill" : "iphone"
                                    )
                                }
                                
                                Button {
                                    showSettings = true
                                } label: {
                                    Label("Player Settings...", systemImage: "gearshape.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AuraTheme.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    
                    Spacer(minLength: 8)
                    
                    // Center Content Area (Fixed constraints to prevent overflowing)
                    ZStack {
                        // Persistent video player host (never unmounts during mode switches).
                        // Video mode: edge to edge across the screen, with a full-screen button.
                        ZStack(alignment: .bottomTrailing) {
                            // Only in Video mode (an almost-transparent player can be paused by WebKit);
                            // otherwise the background player keeps playing
                            if playback.displayMode == .video {
                                YouTubeWebPlayerView(playback: playback, hostID: "player-sheet")
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                Button {
                                    Haptics.light()
                                    showFullScreenVideo = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .padding(10)
                            }
                        }
                        .opacity(playback.displayMode == .video ? 1.0 : 0.001)
                        .allowsHitTesting(playback.displayMode == .video)
                        
                        if playback.displayMode == .audio {
                            // Scalable Album Artwork
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(AuraTheme.surfaceElevated)
                                    .shadow(color: AuraTheme.primary.opacity(playback.isPlaying ? 0.35 : 0.08), radius: 24, x: 0, y: 12)
                                
                                if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
                                   let url = URL(string: artStr) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: artworkDimension, height: artworkDimension)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                        } else {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 54))
                                                .foregroundColor(AuraTheme.textTertiary)
                                        }
                                    }
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 54))
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                            }
                            .frame(width: artworkDimension, height: artworkDimension)
                            .scaleEffect(playback.isPlaying ? 1.0 : 0.88)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: playback.isPlaying)
                        } else if playback.displayMode == .lyrics {
                            LyricsView(playback: playback)
                        }
                    }
                    // Video gets the full screen width (16:9); artwork / lyrics keep their size
                    .frame(height: playback.displayMode == .video
                           ? UIScreen.main.bounds.width * 9 / 16
                           : artworkDimension + 20)
                    
                    Spacer(minLength: 12)
                    
                    if let error = playback.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.75), in: Capsule())
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Track Title, Artist, & Favorite Heart
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .lineLimit(1)
                            
                            Text(track.artist)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AuraTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        
                        // Is this the right video for the song? 👍 always play it, 👎 try the next best
                        if track.sourceType == .youtube {
                            Button {
                                Haptics.light()
                                playback.confirmCurrentVideo()
                            } label: {
                                Image(systemName: playback.isCurrentVideoConfirmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: 19))
                                    .foregroundColor(playback.isCurrentVideoConfirmed ? .green : AuraTheme.textSecondary)
                                    .frame(width: 40, height: 44)
                            }
                            Button {
                                Haptics.medium()
                                playback.rejectCurrentVideo()
                            } label: {
                                Image(systemName: "hand.thumbsdown")
                                    .font(.system(size: 19))
                                    .foregroundColor(AuraTheme.textSecondary)
                                    .frame(width: 40, height: 44)
                            }
                        }
                        
                        Button {
                            Haptics.light()
                            playlistStore.toggleFavorite(track: track)
                        } label: {
                            Image(systemName: playlistStore.isTrackFavorite(track) ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundColor(playlistStore.isTrackFavorite(track) ? AuraTheme.primary : AuraTheme.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 28)
                    
                    // Scrubber Bar & Timestamps
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { currentProgress },
                                set: { val in
                                    isDraggingSlider = true
                                    sliderValue = val
                                }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if !editing {
                                    let targetSec = sliderValue * playback.duration
                                    playback.seek(to: targetSec)
                                    isDraggingSlider = false
                                }
                            }
                        )
                        .tint(AuraTheme.primary)
                        
                        HStack {
                            Text(formatTime(isDraggingSlider ? sliderValue * playback.duration : playback.currentTime))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(AuraTheme.textTertiary)
                            Spacer()
                            Text(formatTime(playback.duration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(AuraTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    
                    // Media Controls
                    HStack {
                        Spacer()
                        
                        // Shuffle
                        Button {
                            Haptics.light()
                            playback.toggleShuffle()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(playback.isShuffled ? AuraTheme.primary : AuraTheme.textTertiary)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        // Previous
                        Button {
                            Haptics.light()
                            playback.playPrevious()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        // Play / Pause Large Glow Circle
                        Button {
                            Haptics.medium()
                            playback.togglePlayPause()
                        } label: {
                            ZStack {
                                // Frosted white glass button, like light caught in a bubble
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    .frame(width: 70, height: 70)
                                    .shadow(color: Color(hex: 0x3A2E9A).opacity(0.45), radius: 16, x: 0, y: 8)
                                
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(Color(hex: 0x7B6BE0))
                                    .offset(x: playback.isPlaying ? 0 : 2)
                            }
                        }
                        .frame(width: 70, height: 70)
                        
                        Spacer()
                        
                        // Next
                        Button {
                            Haptics.light()
                            playback.playNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        // Repeat
                        Button {
                            Haptics.light()
                            playback.repeatMode = (playback.repeatMode + 1) % 3
                        } label: {
                            Image(systemName: playback.repeatMode == 2 ? "repeat.1" : "repeat")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(playback.repeatMode > 0 ? AuraTheme.primary : AuraTheme.textTertiary)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            VideoFullScreenView(playback: playback)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(playlistStore: playlistStore)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(track: track, playlistStore: playlistStore)
        }
        .sheet(isPresented: $showChangeVideo) {
            ChangeVideoLinkSheet(track: track, store: playlistStore, playback: playback)
        }
        .sheet(isPresented: $showTrimTimes) {
            TrimTimesSheet(track: track, store: playlistStore, playback: playback)
        }
        )
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 && !seconds.isNaN else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
