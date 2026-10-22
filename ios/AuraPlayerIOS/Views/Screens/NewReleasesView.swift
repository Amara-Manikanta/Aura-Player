import SwiftUI

public struct NewReleasesView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager
    
    @State private var selectedLanguage: String = "Telugu"
    @State private var period: ReleasePeriod = .week
    @State private var releases: [NewRelease] = []
    @State private var isLoading: Bool = false
    @State private var isGridView: Bool = false
    @State private var trackForPlaylistSheet: MediaTrack?
    
    private let languages = ["Telugu", "Hindi", "Tamil", "English", "Kannada", "Malayalam", "Punjabi"]
    
    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }
    
    private var allTracks: [MediaTrack] {
        releases.map { item in
            let cleaned = MetadataCleaner.clean(title: item.video.title, artist: item.video.channel)
            return MediaTrack(
                title: cleaned.cleanTitle,
                artist: cleaned.primaryArtist,
                duration: item.video.duration,
                sourceType: .youtube,
                mediaType: .video,
                originalURL: item.video.url,
                thumbnailURL: item.video.thumbnailURL,
                youtubeId: item.video.id
            )
        }
    }
    
    public var body: some View {
        ZStack {
            AuraTheme.backgroundDark.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Filter Bar
                VStack(spacing: 12) {
                    // Language Horizontal Scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(languages, id: \.self) { lang in
                                Button {
                                    Haptics.light()
                                    selectedLanguage = lang
                                    loadReleases()
                                } label: {
                                    Text(lang)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedLanguage == lang ? AuraTheme.primary : AuraTheme.surfaceElevated)
                                        .foregroundColor(selectedLanguage == lang ? .white : AuraTheme.textSecondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                    
                    // Period Picker & Layout Toggle
                    HStack {
                        Picker("Period", selection: $period) {
                            ForEach(ReleasePeriod.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: period) { _ in
                            loadReleases()
                        }
                        
                        Spacer()
                        
                        Button {
                            Haptics.light()
                            isGridView.toggle()
                        } label: {
                            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                .foregroundColor(AuraTheme.primary)
                                .frame(width: 36, height: 36)
                                .background(AuraTheme.surfaceElevated)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Action Row
                    if !releases.isEmpty {
                        HStack {
                            Text("\(releases.count) latest releases")
                                .font(.system(size: 13))
                                .foregroundColor(AuraTheme.textTertiary)
                            Spacer()
                            Button {
                                Haptics.medium()
                                let tracks = allTracks
                                if let first = tracks.first {
                                    playback.playTrack(first, inQueue: tracks)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12))
                                    Text("Play All")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(AuraTheme.primaryGradient)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 12)
                .background(AuraTheme.surfaceCard.opacity(0.85))
                
                Divider().overlay(AuraTheme.glassBorder)
                
                // Content
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(AuraTheme.primary)
                        Text("Discovering latest \(selectedLanguage) music...")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if releases.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 48))
                            .foregroundColor(AuraTheme.textTertiary)
                        Text("No releases found")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AuraTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isGridView {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(Array(releases.enumerated()), id: \.element.id) { idx, item in
                                let track = allTracks[idx]
                                Button {
                                    Haptics.light()
                                    playback.playTrack(track, inQueue: allTracks)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .bottomTrailing) {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(AuraTheme.surfaceElevated)
                                                .aspectRatio(16/9, contentMode: .fit)
                                            
                                            if let thumb = item.video.thumbnailURL, let url = URL(string: thumb) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .aspectRatio(16/9, contentMode: .fit)
                                                            .clipped()
                                                            .cornerRadius(12)
                                                    }
                                                }
                                            }
                                        }
                                        
                                        Text(track.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AuraTheme.textPrimary)
                                            .lineLimit(2)
                                        
                                        Text(track.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(AuraTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 120)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(releases.enumerated()), id: \.element.id) { idx, item in
                                let track = allTracks[idx]
                                let isCur = (playback.currentTrack?.youtubeId == track.youtubeId)
                                TrackRowView(
                                    track: track,
                                    isCurrent: isCur,
                                    isPlaying: playback.isPlaying,
                                    onTap: {
                                        playback.playTrack(track, inQueue: allTracks)
                                    },
                                    onPlayVideo: {
                                        playback.displayMode = .video
                                        playback.playTrack(track, inQueue: allTracks)
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
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .navigationTitle("New Releases")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if releases.isEmpty {
                loadReleases()
            }
        }
        .sheet(item: $trackForPlaylistSheet) { t in
            AddToPlaylistSheet(track: t, playlistStore: playlistStore)
        }
    }
    
    private func loadReleases() {
        isLoading = true
        Task {
            let res = await YouTubeService.shared.newReleases(language: selectedLanguage, period: period)
            await MainActor.run {
                self.releases = res
                self.isLoading = false
            }
        }
    }
}
