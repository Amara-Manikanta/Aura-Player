import SwiftUI

/// Songs by when they were added to your library (Apple Music's date for imported songs),
/// grouped into Today / This Week / This Month / Earlier.
public struct RecentlyAddedView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    @State private var trackToTrim: MediaTrack?
    
    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }
    
    private static let limit = 300
    
    private var tracks: [MediaTrack] { Array(store.recentlyAddedTracks.prefix(Self.limit)) }
    
    private var groups: [(String, [MediaTrack])] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [String: [MediaTrack]] = [:]
        let order = ["Today", "This Week", "This Month", "Last 3 Months", "Earlier"]
        for t in tracks {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: t.dateAdded), to: calendar.startOfDay(for: now)).day ?? 0
            let key = days <= 0 ? "Today" : days < 7 ? "This Week" : days < 31 ? "This Month" : days < 92 ? "Last 3 Months" : "Earlier"
            buckets[key, default: []].append(t)
        }
        return order.compactMap { key in buckets[key].map { (key, $0) } }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Added").font(.system(size: 26, weight: .bold))
                    Text("Newest songs in your library first").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let first = tracks.first { playback.playTrack(first, inQueue: tracks, context: .none) }
                } label: { Label("Play All", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(tracks.isEmpty)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            Divider()
            
            List {
                ForEach(groups, id: \.0) { title, items in
                    Section {
                        ForEach(items) { track in
                            HStack(spacing: 0) {
                                TrackRowView(
                                    index: (tracks.firstIndex { $0.id == track.id } ?? 0) + 1,
                                    track: track,
                                    isCurrent: playback.currentTrack?.id == track.id,
                                    isPlaying: playback.isPlaying && playback.currentTrack?.id == track.id,
                                    onPlay: { playback.playTrack(track, inQueue: tracks, context: .none) },
                                    onToggleFavorite: { store.toggleFavorite(track: track) },
                                    onChangeVideo: {},
                                    onSetTrim: { trackToTrim = track },
                                    onRemove: {}
                                )
                                Text(track.dateAdded.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                    } header: {
                        Text("\(title)  ·  \(items.count)")
                            .font(.subheadline.bold())
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(item: $trackToTrim) { tr in
            TrimTimesSheet(track: tr, store: store, playback: playback)
        }
    }
}
