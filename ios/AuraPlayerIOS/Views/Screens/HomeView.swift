import SwiftUI

public struct HomeView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var trackForPlaylistSheet: MediaTrack?
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Aura Player")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(AuraTheme.textPrimary)
                                Text("Listen without limits")
                                    .font(.system(size: 14))
                                    .foregroundColor(AuraTheme.textSecondary)
                            }
                            Spacer()
                            
                            Circle()
                                .fill(AuraTheme.primaryGradient)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Playlists Grid (From macOS Library)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Your Playlists")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AuraTheme.textPrimary)
                                Spacer()
                                NavigationLink {
                                    LibraryView(playlistStore: playlistStore, playback: playback)
                                } label: {
                                    Text("See All")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AuraTheme.primary)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(playlistStore.playlists.prefix(8)) { pl in
                                    NavigationLink {
                                        PlaylistDetailView(playlist: pl, playlistStore: playlistStore, playback: playback)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: pl.iconName)
                                                .font(.system(size: 20))
                                                .foregroundColor(AuraTheme.primary)
                                                .frame(width: 44, height: 44)
                                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pl.name)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(AuraTheme.textPrimary)
                                                    .lineLimit(1)
                                                Text("\(pl.tracks.count) tracks")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(AuraTheme.textTertiary)
                                            }
                                            Spacer()
                                        }
                                        .padding(10)
                                        .liquidGlass(cornerRadius: 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Recent / Most Played Tracks
                        let mostPlayed = playlistStore.mostPlayedTracks
                        if !mostPlayed.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Most Played")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .padding(.horizontal, 20)
                                
                                LazyVStack(spacing: 4) {
                                    ForEach(mostPlayed.prefix(8)) { track in
                                        let isCur = (playback.currentTrack?.id == track.id)
                                        TrackRowView(
                                            track: track,
                                            isCurrent: isCur,
                                            isPlaying: playback.isPlaying,
                                            onTap: {
                                                playback.playTrack(track, inQueue: mostPlayed, context: .none)
                                            },
                                            onPlayVideo: {
                                                playback.displayMode = .video
                                                playback.playTrack(track, inQueue: mostPlayed, context: .none)
                                            },
                                            onAddToPlaylist: {
                                                trackForPlaylistSheet = track
                                            },
                                            onToggleFavorite: {
                                                playlistStore.toggleFavorite(track: track)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        
                        Spacer(minLength: 120)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $trackForPlaylistSheet) { t in
                AddToPlaylistSheet(track: t, playlistStore: playlistStore)
            }
        }
    }
}
