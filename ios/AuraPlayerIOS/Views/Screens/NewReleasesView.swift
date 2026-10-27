import SwiftUI

/// Songs uploaded to YouTube this week / this month, per language (same search and filters as the Mac app).
public struct NewReleasesView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @ObservedObject var playback: PlaybackManager

    @AppStorage("newReleasesLanguage") private var selectedLanguage: String = "Telugu"
    @State private var period: ReleasePeriod = .week
    @State private var releases: [NewRelease] = []
    @State private var isLoading: Bool = false
    @State private var trackForPlaylistSheet: MediaTrack?

    private let languages = ["Telugu", "Hindi", "Tamil", "English", "Kannada", "Malayalam", "Punjabi"]

    public init(playlistStore: PlaylistStore, playback: PlaybackManager) {
        self.playlistStore = playlistStore
        self.playback = playback
    }

    private var allTracks: [MediaTrack] { releases.map { DiscoverRow.track(from: $0.video) } }

    public var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(languages, id: \.self) { lang in
                                Button {
                                    Haptics.light()
                                    selectedLanguage = lang
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

                    HStack(spacing: 10) {
                        Picker("Period", selection: $period) {
                            ForEach(ReleasePeriod.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)

                        Spacer()

                        Button {
                            Haptics.medium()
                            let tracks = allTracks
                            if let first = tracks.first {
                                playback.playTrack(first, inQueue: tracks, context: .none)
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AuraTheme.primaryGradient)
                                .clipShape(Capsule())
                        }
                        .disabled(releases.isEmpty)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)

                if isLoading && releases.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView().tint(AuraTheme.primary)
                        Text("Searching YouTube for new \(selectedLanguage) songs…")
                            .font(.system(size: 14))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if releases.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 44))
                            .foregroundColor(AuraTheme.textTertiary)
                        Text("No new \(selectedLanguage) songs found \(period.rawValue.lowercased()).")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AuraTheme.textPrimary)
                        if period == .week {
                            Button("Show This Month") { period = .month }
                                .foregroundColor(AuraTheme.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let tracks = allTracks
                    ScrollView(showsIndicators: false) {
                        Text("\(releases.count) songs uploaded \(period.rawValue.lowercased())")
                            .font(.system(size: 12))
                            .foregroundColor(AuraTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                        LazyVStack(spacing: 2) {
                            ForEach(Array(releases.enumerated()), id: \.element.id) { idx, item in
                                DiscoverRow(
                                    video: item.video, track: tracks[idx],
                                    views: item.views, uploadedAgo: item.uploadedAgo,
                                    isCurrent: playback.currentTrack?.youtubeId == item.video.id,
                                    isPlaying: playback.isPlaying,
                                    onPlay: { playback.playTrack(tracks[idx], inQueue: tracks, context: .none) },
                                    onAdd: { trackForPlaylistSheet = tracks[idx] }
                                )
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .refreshable { await load(force: true) }
                }
            }
        }
        .navigationTitle("New Releases")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(selectedLanguage)|\(period.rawValue)") { await load(force: false) }
        .sheet(item: $trackForPlaylistSheet) { t in
            AddToPlaylistSheet(track: t, playlistStore: playlistStore)
        }
    }

    private func load(force: Bool) async {
        isLoading = true
        if !force { releases = [] }
        releases = await YouTubeService.shared.newReleases(language: selectedLanguage, period: period, forceRefresh: force)
        isLoading = false
    }

    static func formatViews(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM views", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK views", Double(n) / 1_000)
        default: return "\(n) views"
        }
    }
}
