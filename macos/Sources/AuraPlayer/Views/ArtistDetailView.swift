import SwiftUI

public struct ArtistDetailView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    let artistName: String
    let onBack: () -> Void
    
    private var artistGroup: ArtistGroup? {
        store.allArtists.first { $0.name == artistName }
    }
    
    public init(store: PlaylistStore, playback: PlaybackManager, artistName: String, onBack: @escaping () -> Void) {
        self.store = store
        self.playback = playback
        self.artistName = artistName
        self.onBack = onBack
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("All Artists")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    // Artist photo
                    ArtistAvatar(name: artistName, size: 90, fallbackArtworkURL: artistGroup?.sampleArtworkURL)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARTIST")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        Text(artistName)
                            .font(.system(size: 26, weight: .bold))
                        
                        HStack(spacing: 8) {
                            Text("\(artistGroup?.trackCount ?? 0) songs")
                            if let plays = artistGroup?.totalPlayCount, plays > 0 {
                                Text("•")
                                Label("\(plays) total plays", systemImage: "flame.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            if let tracks = artistGroup?.tracks, let first = tracks.first {
                                playback.playTrack(first, inQueue: tracks, context: .none)
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
                        
                        Button {
                            if var tracks = artistGroup?.tracks {
                                tracks.shuffle()
                                if let first = tracks.first {
                                    playback.playTrack(first, inQueue: tracks, context: .none)
                                }
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
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Track List
            if let tracks = artistGroup?.tracks {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRowWithPlayCountView(
                            index: index + 1,
                            track: track,
                            isCurrent: playback.currentTrack?.id == track.id,
                            isPlaying: playback.isPlaying && playback.currentTrack?.id == track.id,
                            onPlay: {
                                playback.playTrack(track, inQueue: tracks, context: .none)
                            },
                            onToggleFavorite: {
                                store.toggleFavorite(track: track)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

public struct TrackRowWithPlayCountView: View {
    public let index: Int
    public let track: MediaTrack
    public let isCurrent: Bool
    public let isPlaying: Bool
    public let onPlay: () -> Void
    public let onToggleFavorite: () -> Void
    
    @State private var isHovered: Bool = false
    
    public var body: some View {
        HStack(spacing: 12) {
            // Index or waveform
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
                    if track.totalPlays > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 9))
                            Text("\(track.totalPlays) plays")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    
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
    }
}
