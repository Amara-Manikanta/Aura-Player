import SwiftUI

public struct ArtistsView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    @Binding var selectedArtist: String?
    
    @State private var searchText: String = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)
    ]
    
    public init(store: PlaylistStore, playback: PlaybackManager, selectedArtist: Binding<String?>) {
        self.store = store
        self.playback = playback
        self._selectedArtist = selectedArtist
    }
    
    private var filteredArtists: [ArtistGroup] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.allArtists
        }
        return store.allArtists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Singers & Artists")
                        .font(.system(size: 26, weight: .bold))
                    Text("\(store.allArtists.count) artists in your library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search singer...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
            .background(.ultraThinMaterial)
            
            Divider()
            
            if filteredArtists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("No Artists Found")
                        .font(.headline)
                    Text("Import playlists from Apple Music or add songs to see singers here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(filteredArtists) { artist in
                            ArtistCardView(
                                artist: artist,
                                onSelect: {
                                    selectedArtist = artist.name
                                },
                                onPlay: {
                                    if let first = artist.tracks.first {
                                        playback.playTrack(first, inQueue: artist.tracks, context: .none)
                                    }
                                }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
    }
}

public struct ArtistCardView: View {
    public let artist: ArtistGroup
    public let onSelect: () -> Void
    public let onPlay: () -> Void
    
    @State private var isHovered: Bool = false
    
    public var body: some View {
        VStack(spacing: 10) {
            // Circular artist photo (initials until it loads), with a play button on hover
            ZStack {
                ArtistAvatar(name: artist.name, size: 120, fallbackArtworkURL: artist.sampleArtworkURL)
                
                // Play overlay on hover
                if isHovered {
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 120, height: 120)
                    
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            VStack(spacing: 2) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 4) {
                    Text("\(artist.trackCount) songs")
                    if artist.totalPlayCount > 0 {
                        Text("•")
                        Text("\(artist.totalPlayCount) plays")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
    }
}
