import SwiftUI

public struct MostPlayedView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP SONGS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text("Most Played")
                        .font(.system(size: 26, weight: .bold))
                    Text("\(store.mostPlayedTracks.count) songs with play history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !store.mostPlayedTracks.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            if let first = store.mostPlayedTracks.first {
                                playback.playTrack(first, inQueue: store.mostPlayedTracks, context: .none)
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(LinearGradient(colors: [Color.orange, Color.red], startPoint: .leading, endPoint: .trailing))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            var shuffled = store.mostPlayedTracks
                            shuffled.shuffle()
                            if let first = shuffled.first {
                                playback.playTrack(first, inQueue: shuffled, context: .none)
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
            
            if store.mostPlayedTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "flame")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text("No Play History Yet")
                        .font(.headline)
                    Text("Listen to songs for at least 10 seconds to track your most played music.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(store.mostPlayedTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRowWithPlayCountView(
                            index: index + 1,
                            track: track,
                            isCurrent: playback.currentTrack?.id == track.id,
                            isPlaying: playback.isPlaying && playback.currentTrack?.id == track.id,
                            onPlay: {
                                playback.playTrack(track, inQueue: store.mostPlayedTracks, context: .none)
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
