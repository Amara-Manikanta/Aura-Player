import SwiftUI

public struct BottomControlBar: View {
    @Bindable var playback: PlaybackManager
    @Bindable var store: PlaylistStore
    @Binding var showVideoView: Bool
    
    @State private var isDraggingScrubber: Bool = false
    @State private var scrubTime: TimeInterval = 0
    
    public init(playback: PlaybackManager, store: PlaylistStore, showVideoView: Binding<Bool>) {
        self.playback = playback
        self.store = store
        self._showVideoView = showVideoView
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            // Scrubber Slider
            HStack(spacing: 8) {
                Text(formatTime(isDraggingScrubber ? scrubTime : playback.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                Slider(
                    value: Binding(
                        get: { isDraggingScrubber ? scrubTime : playback.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(playback.duration, 1.0)
                ) { editing in
                    isDraggingScrubber = editing
                    if !editing {
                        playback.seek(to: scrubTime)
                    }
                }
                .accentColor(.purple)
                
                Text(formatTime(playback.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .leading)
            }
            .padding(.horizontal, 16)
            
            // Main Controls Bar
            HStack(spacing: 16) {
                // Left: Track Info & Favorite Heart
                HStack(spacing: 12) {
                    if let track = playback.currentTrack {
                        Group {
                            if let thumb = playback.currentArtworkURL, let url = URL(string: thumb) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                TrackArtworkView(track: track, size: 44, cornerRadius: 8)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            
                            Text(track.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)   // the title shrinks first, so the buttons always stay visible
                        
                        Button {
                            store.toggleFavorite(track: track)
                        } label: {
                            Image(systemName: store.isFavorite(track: track) ? "heart.fill" : "heart")
                                .foregroundStyle(store.isFavorite(track: track) ? .red : .secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Favorite")
                        
                        // Is this the right video for the song?
                        if track.sourceType == .youtube {
                            let confirmed = playback.isCurrentVideoConfirmed
                            Button {
                                playback.confirmCurrentVideo()
                            } label: {
                                Image(systemName: confirmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .foregroundStyle(confirmed ? .green : .secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .help("Right song: always play this video for it")
                            
                            Button {
                                playback.rejectCurrentVideo()
                            } label: {
                                Image(systemName: "hand.thumbsdown")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .help("Wrong song or video: try the next best match")
                        }
                        
                        // Start/end time, video, playlists… for this song
                        CurrentSongMenu(playback: playback, iconSize: 13)
                    } else {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Text("Ready to play")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 200, alignment: .leading)
                    }
                }
                .frame(width: 330, alignment: .leading)
                
                Spacer()
                
                // Center Controls
                HStack(spacing: 20) {
                    Button {
                        playback.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: playback.isShuffle ? .bold : .regular))
                            .foregroundStyle(playback.isShuffle ? Color.purple : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Shuffle")
                    
                    Button {
                        playback.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Previous")
                    
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)
                                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
                            
                            if playback.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .colorInvert()
                            } else {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: playback.isPlaying ? 0 : 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(playback.isPlaying ? "Pause" : "Play")
                    
                    Button {
                        playback.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Next")
                    
                    Button {
                        playback.cycleRepeatMode()
                    } label: {
                        Image(systemName: playback.repeatMode.iconName)
                            .font(.system(size: 14, weight: playback.repeatMode != .off ? .bold : .regular))
                            .foregroundStyle(playback.repeatMode != .off ? Color.purple : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Repeat Mode")
                }
                
                Spacer()
                
                // Right Controls (Mini Player + Volume + View Switcher)
                HStack(spacing: 14) {
                    MiniPlayerButton()
                    
                    // Volume Control
                    HStack(spacing: 6) {
                        Button {
                            playback.toggleMute()
                        } label: {
                            Image(systemName: volumeIcon)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Slider(
                            value: Binding(
                                get: { Double(playback.volume) },
                                set: { playback.volume = Float($0) }
                            ),
                            in: 0...1.0
                        )
                        .frame(width: 75)
                        .accentColor(.purple)
                    }
                    
                    Divider().frame(height: 20)
                    
                    // Video vs Audio View Toggle
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showVideoView.toggle()
                            playback.setVideoViewActive(showVideoView)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showVideoView ? "tv.fill" : "music.note")
                            Text(showVideoView ? "Video" : "Music")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(showVideoView ? Color.purple.opacity(0.8) : Color.white.opacity(0.12))
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help(showVideoView ? "Switch to Music View" : "Switch to Video View")
                }
                .frame(width: 280, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .top
        )
    }
    
    private var volumeIcon: String {
        if playback.isMuted || playback.volume == 0 {
            return "speaker.slash.fill"
        } else if playback.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playback.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Opens the small always-on-top player window.
struct MiniPlayerButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button {
            openWindow(id: "mini-player")
        } label: {
            Image(systemName: "pip.enter")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Mini Player (⇧⌘M)")
    }
}
