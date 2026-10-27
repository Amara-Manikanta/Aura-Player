import SwiftUI

public struct ArtistsView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    public var body: some View {
        ZStack {
            AuraBackground()
            
            ScrollView(showsIndicators: false) {
                // Each singer separately (a duet is listed under both), most songs first, like the Mac app
                let artists = playlistStore.allArtists.map { ($0.name, $0.tracks) }
                
                if artists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 48))
                            .foregroundColor(AuraTheme.textTertiary)
                        Text("No Artists Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AuraTheme.textPrimary)
                        Text("Add tracks to your playlists to see artists.")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(artists, id: \.0) { artist, tracks in
                            NavigationLink {
                                ArtistDetailView(
                                    artistName: artist,
                                    tracks: tracks,
                                    playlistStore: playlistStore,
                                    playback: playback
                                )
                            } label: {
                                VStack(spacing: 8) {
                                    ArtistAvatar(name: artist, size: 90, fallbackArtworkURL: tracks.first?.thumbnailURL)
                                        .shadow(color: AuraTheme.primary.opacity(0.15), radius: 10)
                                    
                                    Text(artist)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AuraTheme.textPrimary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 100)
                                    
                                    Text("\(tracks.count) songs")
                                        .font(.system(size: 11))
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
    }
}
