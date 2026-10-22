import SwiftUI

public struct FullPlayerSheet: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showAddToPlaylist: Bool = false
    @State private var showChangeVideo: Bool = false
    @State private var showTrimTimes: Bool = false
    
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
                // Background AMOLED Black and Warm Ambient Gradient
                AuraTheme.backgroundDark.ignoresSafeArea()
                AuraTheme.ambientGradient.ignoresSafeArea()
                
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
                            
                            Button {
                                showTrimTimes = true
                            } label: {
                                Label("Trim Audio (Start/End)", systemImage: "scissors")
                            }
                            
                            Button {
                                playlistStore.toggleFavorite(track: track)
                            } label: {
                                Label(playlistStore.isTrackFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
                                      systemImage: playlistStore.isTrackFavorite(track) ? "heart.slash" : "heart")
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
                        // Persistent video player host (never unmounts during mode switches)
                        YouTubeWebPlayerView(playback: playback)
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(AuraTheme.glassBorder, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 16)
                            .padding(.horizontal, 16)
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
                    .frame(height: artworkDimension + 20)
                    
                    Spacer(minLength: 12)
                    
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
                                Circle()
                                    .fill(AuraTheme.primaryGradient)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: AuraTheme.primary.opacity(0.45), radius: 14, x: 0, y: 6)
                                
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: playback.isPlaying ? 0 : 2)
                            }
                        }
                        .frame(width: 64, height: 64)
                        
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
