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
            AuraTheme.backgroundDark.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                let artists = playlistStore.artistsMap.sorted { $0.key < $1.key }
                
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
                        ForEach(artists, id: \.key) { artist, tracks in
                            NavigationLink {
                                ArtistDetailView(
                                    artistName: artist,
                                    tracks: tracks,
                                    playlistStore: playlistStore,
                                    playback: playback
                                )
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(AuraTheme.surfaceElevated)
                                            .frame(width: 90, height: 90)
                                            .shadow(color: AuraTheme.primary.opacity(0.15), radius: 10)
                                        
                                        let photoURL = playlistStore.artistPhotos[artist] ?? tracks.first?.thumbnailURL
                                        if let photo = photoURL, let url = URL(string: photo) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 90, height: 90)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "music.mic")
                                                        .foregroundColor(AuraTheme.primary)
                                                }
                                            }
                                        } else {
                                            Image(systemName: "music.mic")
                                                .foregroundColor(AuraTheme.primary)
                                        }
                                    }
                                    
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
