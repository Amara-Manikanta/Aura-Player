import SwiftUI

public struct ArtistDetailView: View {
    public let artistName: String
    public let tracks: [MediaTrack]
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var trackForPlaylistSheet: MediaTrack?
    
    public init(artistName: String, tracks: [MediaTrack], playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.artistName = artistName
        self.tracks = tracks
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    public var body: some View {
        ZStack {
            AuraTheme.backgroundDark.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Avatar
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AuraTheme.surfaceElevated)
                                .frame(width: 140, height: 140)
                                .shadow(color: AuraTheme.primary.opacity(0.3), radius: 20)
                            
                            let photoURL = playlistStore.artistPhotos[artistName] ?? tracks.first?.thumbnailURL
                            if let photo = photoURL, let url = URL(string: photo) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 140, height: 140)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(AuraTheme.primary)
                                    }
                                }
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(AuraTheme.primary)
                            }
                        }
                        
                        Text(artistName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AuraTheme.textPrimary)
                        
                        Text("\(tracks.count) Songs Available")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                    .padding(.top, 16)
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        Button {
                            Haptics.medium()
                            if let first = tracks.first {
                                playback.playTrack(first, inQueue: tracks)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AuraTheme.primaryGradient)
                            .cornerRadius(25)
                        }
                        
                        Button {
                            Haptics.medium()
                            playback.isShuffled = true
                            let shuffled = tracks.shuffled()
                            if let first = shuffled.first {
                                playback.playTrack(first, inQueue: shuffled)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AuraTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AuraTheme.surfaceElevated)
                            .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Track List
                    LazyVStack(spacing: 4) {
                        ForEach(tracks) { track in
                            let isCur = (playback.currentTrack?.id == track.id)
                            TrackRowView(
                                track: track,
                                isCurrent: isCur,
                                isPlaying: playback.isPlaying,
                                onTap: {
                                    playback.playTrack(track, inQueue: tracks)
                                },
                                onPlayVideo: {
                                    playback.displayMode = .video
                                    playback.playTrack(track, inQueue: tracks)
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
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $trackForPlaylistSheet) { t in
            AddToPlaylistSheet(track: t, playlistStore: playlistStore)
        }
    }
}
