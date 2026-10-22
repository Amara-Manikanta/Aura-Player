import SwiftUI

public struct TrackRowView: View {
    public let track: MediaTrack
    public let isCurrent: Bool
    public let isPlaying: Bool
    public let onTap: () -> Void
    public let onPlayVideo: () -> Void
    public let onAddToPlaylist: () -> Void
    public let onToggleFavorite: () -> Void
    public let onRemove: (() -> Void)?
    
    @State private var showChangeVideo: Bool = false
    @State private var showTrimTimes: Bool = false
    
    public init(
        track: MediaTrack,
        isCurrent: Bool,
        isPlaying: Bool,
        onTap: @escaping () -> Void,
        onPlayVideo: @escaping () -> Void,
        onAddToPlaylist: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.track = track
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.onTap = onTap
        self.onPlayVideo = onPlayVideo
        self.onAddToPlaylist = onAddToPlaylist
        self.onToggleFavorite = onToggleFavorite
        self.onRemove = onRemove
    }
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Artwork Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AuraTheme.surfaceElevated)
                        .frame(width: 52, height: 52)
                    
                    if let thumb = track.effectiveThumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 52, height: 52)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            default:
                                Image(systemName: "music.note")
                                    .foregroundColor(AuraTheme.textTertiary)
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .foregroundColor(AuraTheme.textTertiary)
                    }
                    
                    if isCurrent && isPlaying {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AuraTheme.primary)
                            .symbolEffect(.variableColor.iterative.reversing)
                    }
                }
                
                // Track Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold))
                        .foregroundColor(isCurrent ? AuraTheme.primary : AuraTheme.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(track.artist)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(AuraTheme.textSecondary)
                            .lineLimit(1)
                        
                        if let movie = track.movieName, !movie.isEmpty {
                            Text("• \(movie)")
                                .font(.system(size: 12))
                                .foregroundColor(AuraTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Duration & Context Menu
                HStack(spacing: 8) {
                    if track.duration > 0 {
                        Text(track.formattedDuration)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(AuraTheme.textTertiary)
                    }
                    
                    Menu {
                        Button {
                            onPlayVideo()
                        } label: {
                            Label("Play Video", systemImage: "play.rectangle.fill")
                        }
                        
                        Button {
                            onAddToPlaylist()
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                        
                        Button {
                            onToggleFavorite()
                        } label: {
                            Label(track.isFavorite ? "Remove from Favorites" : "Favorite", systemImage: track.isFavorite ? "heart.slash" : "heart.fill")
                        }
                        
                        Divider()
                        
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
                        
                        if let onRemove = onRemove {
                            Divider()
                            Button(role: .destructive) {
                                onRemove()
                            } label: {
                                Label("Remove from Playlist", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AuraTheme.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isCurrent ? AuraTheme.primary.opacity(0.12) : Color.clear)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showChangeVideo) {
            ChangeVideoLinkSheet(track: track, store: PlaylistStore.shared, playback: PlaybackManager.shared)
        }
        .sheet(isPresented: $showTrimTimes) {
            TrimTimesSheet(track: track, store: PlaylistStore.shared, playback: PlaybackManager.shared)
        }
    }
}
