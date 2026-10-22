import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackManager
    public let onExpand: () -> Void
    
    public init(playback: PlaybackManager, onExpand: @escaping () -> Void) {
        self.playback = playback
        self.onExpand = onExpand
    }
    
    private var progress: Double {
        guard playback.duration > 0 else { return 0 }
        return (playback.currentTime / playback.duration).clamped(to: 0...1)
    }
    
    public var body: some View {
        guard let track = playback.currentTrack else { return AnyView(EmptyView()) }
        
        return AnyView(
            Button(action: {
                Haptics.light()
                onExpand()
            }) {
                ZStack(alignment: .top) {
                    // Glass Background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AuraTheme.surfaceCard.opacity(0.92))
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AuraTheme.glassBorder, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                    
                    // Top Micro-Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(AuraTheme.glassBorder)
                                .frame(height: 2.5)
                            
                            Rectangle()
                                .fill(AuraTheme.primaryGradient)
                                .frame(width: geo.size.width * progress, height: 2.5)
                        }
                    }
                    .frame(height: 2.5)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Player Content Row
                    HStack(spacing: 12) {
                        // Artwork
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AuraTheme.surfaceElevated)
                                .frame(width: 46, height: 46)
                            
                            if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
                               let url = URL(string: artStr) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 46, height: 46)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    } else {
                                        Image(systemName: "music.note")
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                }
                            }
                        }
                        
                        // Title & Artist
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .lineLimit(1)
                            
                            Text(track.artist)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(AuraTheme.textSecondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Controls: Play/Pause and Next
                        HStack(spacing: 16) {
                            Button {
                                Haptics.medium()
                                playback.togglePlayPause()
                            } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .frame(width: 36, height: 36)
                            }
                            
                            Button {
                                Haptics.light()
                                playback.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AuraTheme.textSecondary)
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.trailing, 6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: 64)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
