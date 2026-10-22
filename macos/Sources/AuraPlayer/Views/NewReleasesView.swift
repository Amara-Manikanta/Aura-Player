import SwiftUI

/// Songs uploaded to YouTube this week / this month, per language.
public struct NewReleasesView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager

    @AppStorage("newReleasesLanguage") private var language: String = "Telugu"
    @State private var period: YouTubeService.ReleasePeriod = .week
    @State private var items: [YouTubeService.NewRelease] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var notice: String?
    @AppStorage("newReleasesAsCards") private var showCards = true

    private static let languages = ["Telugu", "Hindi", "Tamil", "Kannada", "Malayalam", "English", "Punjabi"]

    private let embedded: Bool
    
    public init(store: PlaylistStore, playback: PlaybackManager, embedded: Bool = false) {
        self.store = store
        self.playback = playback
        self.embedded = embedded
    }

    private var tracks: [MediaTrack] { items.map { Self.track(from: $0.video) } }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: "\(language)|\(period.rawValue)") { await load(force: false) }
        .alert("New Releases", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if !embedded {
                        Text("New Releases")
                            .font(.system(size: 26, weight: .bold))
                    }
                    Text(isLoading ? "Looking for new songs…" : "\(items.count) songs uploaded \(period.rawValue.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $period) {
                    ForEach(YouTubeService.ReleasePeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                Button {
                    if let first = tracks.first { playback.playTrack(first, inQueue: tracks, context: .none) }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(items.isEmpty)

                Picker("", selection: $showCards) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
                .help("Cards or list")
                
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Check YouTube again")
                .disabled(isLoading)
            }

            // Language chips
            HStack(spacing: 8) {
                ForEach(Self.languages, id: \.self) { lang in
                    Button {
                        language = lang
                    } label: {
                        Text(lang)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(language == lang ? Color.purple : Color.white.opacity(0.08))
                            .foregroundStyle(language == lang ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Searching YouTube for new \(language) songs…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorText, items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(.secondary)
                Text(errorText).font(.caption).foregroundStyle(.secondary)
                Button("Try Again") { Task { await load(force: true) } }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("No new \(language) songs found \(period.rawValue.lowercased()).")
                    .font(.caption).foregroundStyle(.secondary)
                if period == .week {
                    Button("Show This Month") { period = .month }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if showCards {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], spacing: 22) {
                    ForEach(items) { item in
                        ReleaseCard(
                            item: item,
                            isCurrent: playback.currentTrack?.youtubeId == item.video.id,
                            isPlaying: playback.isPlaying,
                            playlists: store.playlists,
                            onPlay: { playback.playTrack(Self.track(from: item.video), inQueue: tracks, context: .none) },
                            onAdd: { pl in add(Self.track(from: item.video), to: pl) }
                        )
                    }
                }
                .padding(20)
            }
        } else {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(_ item: YouTubeService.NewRelease, index: Int) -> some View {
        let track = Self.track(from: item.video)
        let isCurrent = playback.currentTrack?.youtubeId == item.video.id
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)

            AsyncImage(url: URL(string: item.video.thumbnailURL ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.video.title)
                    .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Color.purple : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.video.channel)
                    Text("•")
                    Text(item.video.formattedDuration)
                    if item.views > 0 {
                        Text("•")
                        Text(Self.formatViews(item.views))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button {
                playback.playTrack(track, inQueue: tracks, context: .none)
            } label: {
                Image(systemName: isCurrent && playback.isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .help("Play")

            Menu {
                ForEach(store.playlists) { pl in
                    Button(pl.name.trimmingCharacters(in: .whitespaces)) { add(track, to: pl) }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add to a playlist")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { playback.playTrack(track, inQueue: tracks, context: .none) }
    }

    private func add(_ track: MediaTrack, to playlist: Playlist) {
        let name = playlist.name.trimmingCharacters(in: .whitespaces)
        if let existing = store.savedSongs(matching: track).first(where: { $0.playlist.id == playlist.id }) {
            notice = "\"\(existing.track.title)\" is already in \(name)."
            return
        }
        store.addTrack(track, to: playlist.id)
        notice = "Added to \(name)."
    }

    private func load(force: Bool) async {
        isLoading = true
        errorText = nil
        do {
            let result = try await YouTubeService.shared.newReleases(language: language, period: period, forceRefresh: force)
            items = result
        } catch {
            errorText = "Couldn't reach YouTube: \(error.localizedDescription)"
        }
        isLoading = false
    }

    static func track(from v: YouTubeSearchResult) -> MediaTrack {
        MediaTrack(
            title: v.title,
            artist: v.channel,
            duration: v.duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: v.url,
            thumbnailURL: v.thumbnailURL,
            youtubeId: v.id
        )
    }

    static func formatViews(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM views", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK views", Double(n) / 1_000)
        default: return "\(n) views"
        }
    }
}

/// Video-style card: big thumbnail with a play button on hover, title, channel and stats.
struct ReleaseCard: View {
    let item: YouTubeService.NewRelease
    let isCurrent: Bool
    let isPlaying: Bool
    let playlists: [Playlist]
    let onPlay: () -> Void
    let onAdd: (Playlist) -> Void
    /// "Because you like …" line (For You)
    var reason: String? = nil
    var onNotInterested: (() -> Void)? = nil
    
    @State private var hovering = false
    @State private var showAddList = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: item.video.thumbnailURL ?? "")) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .scaleEffect(hovering ? 1.04 : 1)
                
                // Play overlay (always shown on the song that's playing)
                if hovering || isCurrent {
                    Color.black.opacity(0.35)
                    Image(systemName: isCurrent && isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Text(item.video.formattedDuration)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? Color.purple : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 12 : 5, y: 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)
            
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.video.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.purple : Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.video.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let reason {
                        Label(reason, systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .lineLimit(1)
                    }
                    if item.views > 0 {
                        Text(NewReleasesView.formatViews(item.views))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                // A pop-up list rather than a menu: menus close as soon as the card redraws (hover, playback)
                Button {
                    showAddList = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .help("Add to a playlist")
                .popover(isPresented: $showAddList, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Playlist")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(playlists) { pl in
                                    Button {
                                        showAddList = false
                                        onAdd(pl)
                                    } label: {
                                        HStack {
                                            Image(systemName: pl.isBuiltIn ? "heart.fill" : "music.note.list")
                                                .foregroundStyle(.purple)
                                                .frame(width: 18)
                                            Text(pl.name.trimmingCharacters(in: .whitespaces))
                                            Spacer()
                                            Text("\(pl.tracks.count)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                        if let onNotInterested {
                            Divider()
                            Button {
                                showAddList = false
                                onNotInterested()
                            } label: {
                                Label("Not Interested", systemImage: "hand.thumbsdown")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: 240)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
