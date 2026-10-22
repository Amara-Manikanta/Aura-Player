import SwiftUI

public struct ForYouView: View {
    @ObservedObject var store: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var suggestions: [RecommendationService.Suggestion] = []
    @State private var trackForPlaylistSheet: MediaTrack?
    
    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraTheme.backgroundDark.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("For You")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                            Text("Algorithmic mixes based on your listening habits")
                                .font(.system(size: 14))
                                .foregroundColor(AuraTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(suggestions) { item in
                                let track = MediaTrack(
                                    title: item.title,
                                    artist: item.channel,
                                    duration: item.duration,
                                    sourceType: .youtube,
                                    mediaType: .video,
                                    originalURL: "https://www.youtube.com/watch?v=\(item.videoId)",
                                    thumbnailURL: "https://i.ytimg.com/vi/\(item.videoId)/hqdefault.jpg",
                                    youtubeId: item.videoId
                                )
                                let isCur = (playback.currentTrack?.youtubeId == track.youtubeId)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if !item.becauseOf.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 10))
                                                .foregroundColor(AuraTheme.primary)
                                            Text("Because you like \(item.becauseOf)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(AuraTheme.primary)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                    
                                    TrackRowView(
                                        track: track,
                                        isCurrent: isCur,
                                        isPlaying: playback.isPlaying,
                                        onTap: {
                                            playback.playTrack(track)
                                        },
                                        onPlayVideo: {
                                            playback.displayMode = .video
                                            playback.playTrack(track)
                                        },
                                        onAddToPlaylist: {
                                            trackForPlaylistSheet = track
                                        },
                                        onToggleFavorite: {
                                            store.toggleFavorite(track: track)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $trackForPlaylistSheet) { t in
                AddToPlaylistSheet(track: t, playlistStore: store)
            }
            .task {
                let loaded = await RecommendationService.shared.loadSuggestions()
                await MainActor.run {
                    self.suggestions = loaded
                }
            }
        }
    }
}
