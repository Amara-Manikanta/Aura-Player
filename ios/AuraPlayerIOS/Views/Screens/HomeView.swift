import SwiftUI

public struct HomeView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var trackForPlaylistSheet: MediaTrack?
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    private var quickPickTracks: [MediaTrack] {
        if let favs = playlistStore.favoritesPlaylist, !favs.tracks.isEmpty {
            return favs.tracks
        }
        // Fall back to first available non-empty playlist
        for pl in playlistStore.playlists where !pl.tracks.isEmpty {
            return Array(pl.tracks.prefix(10))
        }
        return []
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraTheme.backgroundDark.ignoresSafeArea()
                
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
                        
                        // Featured / Quick Picks Carousel
                        let picks = quickPickTracks
                        if !picks.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Quick Picks")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AuraTheme.textPrimary)
                                    .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(picks) { track in
                                            Button {
                                                Haptics.light()
                                                playback.playTrack(track, inQueue: picks)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    ZStack(alignment: .bottomTrailing) {
                                                        RoundedRectangle(cornerRadius: 18)
                                                            .fill(AuraTheme.surfaceElevated)
                                                            .frame(width: 150, height: 150)
                                                        
                                                        if let thumb = track.effectiveThumbnailURL, let url = URL(string: thumb) {
                                                            AsyncImage(url: url) { phase in
                                                                if let img = phase.image {
                                                                    img.resizable()
                                                                        .aspectRatio(contentMode: .fill)
                                                                        .frame(width: 150, height: 150)
                                                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                                                }
                                                            }
                                                        } else {
                                                            Image(systemName: "music.note")
                                                                .font(.system(size: 40))
                                                                .foregroundColor(AuraTheme.textTertiary)
                                                        }
                                                        
                                                        Circle()
                                                            .fill(AuraTheme.primary)
                                                            .frame(width: 38, height: 38)
                                                            .overlay(
                                                                Image(systemName: "play.fill")
                                                                    .font(.system(size: 14, weight: .bold))
                                                                    .foregroundColor(.white)
                                                            )
                                                            .padding(10)
                                                            .shadow(color: Color.black.opacity(0.4), radius: 6)
                                                    }
                                                    
                                                    Text(track.title)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(AuraTheme.textPrimary)
                                                        .lineLimit(1)
                                                        .frame(width: 150, alignment: .leading)
                                                    
                                                    Text(track.artist)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(AuraTheme.textSecondary)
                                                        .lineLimit(1)
                                                        .frame(width: 150, alignment: .leading)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
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
                                                .background(AuraTheme.surfaceElevated)
                                                .cornerRadius(12)
                                            
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
                                        .background(AuraTheme.surfaceCard)
                                        .cornerRadius(14)
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
                                                playback.playTrack(track, inQueue: mostPlayed)
                                            },
                                            onPlayVideo: {
                                                playback.displayMode = .video
                                                playback.playTrack(track, inQueue: mostPlayed)
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
