import SwiftUI

public struct RecentlyAddedView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var trackForPlaylistSheet: MediaTrack?
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    private var allTracks: [MediaTrack] {
        playlistStore.recentlyAddedTracks
    }
    
    private var groups: [(String, [MediaTrack])] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [String: [MediaTrack]] = [:]
        let order = ["Today", "This Week", "This Month", "Last 3 Months", "Earlier"]
        
        for t in allTracks {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: t.dateAdded), to: calendar.startOfDay(for: now)).day ?? 0
            let key = days <= 0 ? "Today" : days < 7 ? "This Week" : days < 31 ? "This Month" : days < 92 ? "Last 3 Months" : "Earlier"
            buckets[key, default: []].append(t)
        }
        return order.compactMap { key in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }
    
    public var body: some View {
        ZStack {
            AuraBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Banner
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [Color.teal, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 38))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RECENT ADDITIONS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AuraTheme.textTertiary)
                            Text("Recently Added")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                            Text("\(allTracks.count) songs added to library")
                                .font(.system(size: 13))
                                .foregroundColor(AuraTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Action Buttons (Play All & Shuffle)
                    if !allTracks.isEmpty {
                        HStack(spacing: 16) {
                            Button {
                                Haptics.medium()
                                if let first = allTracks.first {
                                    playback.playTrack(first, inQueue: allTracks, context: .none)
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
                                .background(LinearGradient(colors: [Color.teal, Color.cyan], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(25)
                            }
                            
                            Button {
                                Haptics.medium()
                                playback.isShuffled = true
                                let shuffled = allTracks.shuffled()
                                if let first = shuffled.first {
                                    playback.playTrack(first, inQueue: shuffled, context: .none)
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
                                .liquidGlass(cornerRadius: 25)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Grouped List
                    LazyVStack(spacing: 18) {
                        ForEach(groups, id: \.0) { title, items in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(AuraTheme.textPrimary)
                                    Spacer()
                                    Text("\(items.count) songs")
                                        .font(.system(size: 12))
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                                .padding(.horizontal, 20)
                                
                                ForEach(items) { track in
                                    let isCur = (playback.currentTrack?.id == track.id)
                                    TrackRowView(
                                        track: track,
                                        isCurrent: isCur,
                                        isPlaying: playback.isPlaying,
                                        onTap: {
                                            playback.playTrack(track, inQueue: allTracks, context: .none)
                                        },
                                        onPlayVideo: {
                                            playback.displayMode = .video
                                            playback.playTrack(track, inQueue: allTracks, context: .none)
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
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle("Recently Added")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $trackForPlaylistSheet) { t in
            AddToPlaylistSheet(track: t, playlistStore: playlistStore)
        }
    }
}
