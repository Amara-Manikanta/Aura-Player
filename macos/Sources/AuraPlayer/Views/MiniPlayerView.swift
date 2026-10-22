import SwiftUI
import AppKit

/// Small always-on-top player window. Resizable (drag an edge, or pick Small / Medium / Large) with a
/// choice of background: Apple glass, dark, or the music visualizer.
public struct MiniPlayerView: View {
    @State private var playback = PlaybackManager.shared
    /// Show the song's video in the mini player (YouTube and local video songs)
    @AppStorage("miniPlayerShowsVideo") private var showsVideo = true
    @AppStorage("miniPlayerBackground") private var backgroundStyle = MiniBackground.glass.rawValue
    
    public init() {}
    
    private var background: MiniBackground { MiniBackground(rawValue: backgroundStyle) ?? .glass }
    
    private var canShowVideo: Bool {
        guard let track = playback.currentTrack else { return false }
        return track.sourceType == .youtube || track.mediaType == .video
    }
    
    private var videoVisible: Bool { showsVideo && canShowVideo }
    
    /// Text colour: adaptive on glass (light or dark desktop behind it), white on dark backgrounds
    private var primaryText: Color { background == .glass ? .primary : .white }
    private var secondaryText: Color { background == .glass ? .secondary : .white.opacity(0.7) }
    
    public var body: some View {
        ZStack {
            backgroundLayer
            if videoVisible, let track = playback.currentTrack {
                videoLayout(track)
            } else {
                musicLayout
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: videoVisible ? 260 : 140, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(FloatingWindowConfigurator())
        .onAppear { syncVideoOwnership() }
        .onChange(of: videoVisible) { _, visible in
            syncVideoOwnership()
            MiniWindow.resize(to: visible ? MiniWindow.video : MiniWindow.music)
        }
        .onDisappear {
            // Window closed: hand the video back to the main window
            playback.videoInMiniPlayer = false
        }
    }
    
    /// Video plays in exactly one place: here while the mini player shows it.
    private func syncVideoOwnership() {
        if videoVisible {
            playback.videoInMiniPlayer = true
            playback.setVideoViewActive(true)
        } else if playback.videoInMiniPlayer {
            playback.videoInMiniPlayer = false
        }
    }
    
    // MARK: - Backgrounds
    
    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .glass:
            GlassBackground()
        case .dark:
            Color.black.opacity(0.88)
        case .visualizer:
            ZStack {
                Color.black.opacity(0.85)
                MusicVisualizer(isPlaying: playback.isPlaying).opacity(0.8)
            }
        }
    }
    
    // MARK: - Layouts
    
    // Video fills the space above the controls and grows with the window
    private func videoLayout(_ track: MediaTrack) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                VideoPlayerView(track: track, playback: playback)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            controls(track: track, compact: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
    
    private var musicLayout: some View {
        GeometryReader { geo in
            // Artwork grows with the window (up to the height left after the controls)
            let artSize = max(56, min(geo.size.height - 90, geo.size.width * 0.35, 220))
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    MiniArtwork(playback: playback, size: artSize)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playback.currentTrack?.title ?? "Nothing playing")
                            .font(.system(size: geo.size.width > 480 ? 16 : 13, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                        Text(playback.currentTrack?.artist ?? "Pick a song in AuraPlayer")
                            .font(.system(size: geo.size.width > 480 ? 13 : 11))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 10) {
                        windowMenu
                        CurrentSongMenu(playback: playback, iconColor: secondaryText, iconSize: 13)
                        if canShowVideo { modeButton }
                        expandButton
                    }
                    if playback.currentTrack?.sourceType == .youtube {
                        VStack(spacing: 10) { feedbackButtons }
                    }
                }
                Spacer(minLength: 0)
                ProgressRow(playback: playback)
                TransportButtons(playback: playback, size: geo.size.width > 480 ? 22 : 18)
            }
            .padding(14)
        }
    }
    
    private func controls(track: MediaTrack, compact: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if track.sourceType == .youtube { feedbackButtons }
                windowMenu
                CurrentSongMenu(playback: playback, iconColor: secondaryText, iconSize: 13)
                modeButton
                expandButton
            }
            ProgressRow(playback: playback)
            TransportButtons(playback: playback, size: 15)
        }
    }
    
    // MARK: - Buttons
    
    /// Size presets and background style
    private var windowMenu: some View {
        Menu {
            Section("Size") {
                ForEach(MiniWindow.Preset.allCases, id: \.self) { preset in
                    Button(preset.title) { MiniWindow.resize(to: videoVisible ? preset.videoSize : preset.musicSize) }
                }
            }
            Section("Background") {
                Picker("Background", selection: $backgroundStyle) {
                    ForEach(MiniBackground.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(secondaryText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Size and background")
    }
    
    /// 👍 right video (always play it) / 👎 wrong video (try the next best)
    @ViewBuilder
    private var feedbackButtons: some View {
        let confirmed = playback.isCurrentVideoConfirmed
        Button { playback.confirmCurrentVideo() } label: {
            Image(systemName: confirmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                .foregroundStyle(confirmed ? Color.green : secondaryText)
        }
        .buttonStyle(.plain)
        .help("Right song: always play this video for it")
        Button { playback.rejectCurrentVideo() } label: {
            Image(systemName: "hand.thumbsdown")
                .foregroundStyle(secondaryText)
        }
        .buttonStyle(.plain)
        .help("Wrong song or video: try the next best match")
    }
    
    /// Switch between video and artwork
    private var modeButton: some View {
        Button {
            showsVideo.toggle()
        } label: {
            Image(systemName: showsVideo ? "music.note" : "tv")
                .foregroundStyle(secondaryText)
        }
        .buttonStyle(.plain)
        .help(showsVideo ? "Show artwork instead of video" : "Show the video")
    }
    
    private var expandButton: some View {
        Button {
            MainWindowHelper.showMainWindow()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(secondaryText)
        }
        .buttonStyle(.plain)
        .help("Open the full player")
    }
}

public enum MiniBackground: String, CaseIterable {
    case glass, dark, visualizer
    var title: String {
        switch self {
        case .glass: return "Glass"
        case .dark: return "Dark"
        case .visualizer: return "Visualizer"
        }
    }
}

/// Apple's Liquid Glass on macOS 26+, frosted blur of the desktop behind on older macOS.
struct GlassBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            BehindWindowBlur()
        }
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Finds and resizes the mini player window.
enum MiniWindow {
    enum Preset: CaseIterable {
        case small, medium, large
        var title: String { self == .small ? "Small" : self == .medium ? "Medium" : "Large" }
        var videoSize: CGSize { self == .small ? CGSize(width: 340, height: 300) : self == .medium ? CGSize(width: 480, height: 380) : CGSize(width: 720, height: 520) }
        var musicSize: CGSize { self == .small ? CGSize(width: 320, height: 150) : self == .medium ? CGSize(width: 420, height: 200) : CGSize(width: 560, height: 280) }
    }
    static let video = CGSize(width: 400, height: 330)
    static let music = CGSize(width: 340, height: 170)
    
    @MainActor static func resize(to size: CGSize) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("mini-player") ?? false }) else { return }
        var frame = window.frame
        // keep the top-left corner where it is
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true, animate: true)
    }
}

/// Player in the menu bar: song, progress and controls, one click away from any app.
public struct MenuBarPlayerView: View {
    @State private var playback = PlaybackManager.shared
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MiniArtwork(playback: playback, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.currentTrack?.title ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(playback.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressRow(playback: playback)
            TransportButtons(playback: playback, size: 20)
            Divider()
            HStack {
                Button("Open AuraPlayer") { MainWindowHelper.showMainWindow() }
                Spacer()
                Button("Mini Player") { openWindow(id: "mini-player") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Menu bar icon: animated while music plays.
public struct MenuBarIcon: View {
    @State private var playback = PlaybackManager.shared
    public init() {}
    public var body: some View {
        Image(systemName: playback.isPlaying ? "waveform" : "music.note")
    }
}

// MARK: - Shared pieces

struct MiniArtwork: View {
    let playback: PlaybackManager
    let size: CGFloat

    var body: some View {
        Group {
            if let art = playback.currentArtworkURL, let url = URL(string: art) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) } else { Color.purple.opacity(0.3) }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let track = playback.currentTrack {
                TrackArtworkView(track: track, size: size, cornerRadius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.3))
                    .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.7)))
                    .frame(width: size, height: size)
            }
        }
    }
}

struct ProgressRow: View {
    @Bindable var playback: PlaybackManager
    @State private var dragValue: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.format(dragValue ?? playback.currentTime))
            Slider(
                value: Binding(
                    get: { dragValue ?? playback.currentTime },
                    set: { dragValue = $0 }
                ),
                in: 0...max(playback.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let v = dragValue {
                        playback.seek(to: v)
                        dragValue = nil
                    }
                }
            )
            .controlSize(.mini)
            .tint(.purple)
            Text(Self.format(playback.duration))
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    static func format(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

struct TransportButtons: View {
    @Bindable var playback: PlaybackManager
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 1.6) {
            Button { playback.previous() } label: { Image(systemName: "backward.fill") }
            Button { playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: size * 1.8))
                    .foregroundStyle(.purple)
            }
            Button { playback.next() } label: { Image(systemName: "forward.fill") }
        }
        .font(.system(size: size))
        .buttonStyle(.plain)
        .disabled(playback.currentTrack == nil)
    }
}

enum MainWindowHelper {
    /// Brings the main AuraPlayer window to the front.
    @MainActor static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where !(window.identifier?.rawValue.hasPrefix("mini-player") ?? false) && window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Keeps the mini player above other windows, on every Space, and draggable by its background.
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            // see-through so the glass background shows the desktop
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
