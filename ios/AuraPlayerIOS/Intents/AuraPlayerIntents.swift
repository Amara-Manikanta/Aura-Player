import Foundation
import AppIntents

// MARK: - Play Next Track Intent
public struct PlayNextTrackIntent: AppIntent {
    public static var title: LocalizedStringResource = "Play Next Track"
    public static var description = IntentDescription("Skips to the next song in Aura Player.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PlaybackManager.shared.playNext()
        if let current = PlaybackManager.shared.currentTrack {
            return .result(dialog: "Playing \(current.title)")
        } else {
            return .result(dialog: "Skipped to next track")
        }
    }
}

// MARK: - Play Previous Track Intent
public struct PlayPreviousTrackIntent: AppIntent {
    public static var title: LocalizedStringResource = "Play Previous Track"
    public static var description = IntentDescription("Plays the previous song in Aura Player.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PlaybackManager.shared.playPrevious()
        if let current = PlaybackManager.shared.currentTrack {
            return .result(dialog: "Playing \(current.title)")
        } else {
            return .result(dialog: "Playing previous track")
        }
    }
}

// MARK: - Resume Playback Intent
public struct ResumePlaybackIntent: AppIntent {
    public static var title: LocalizedStringResource = "Resume Playback"
    public static var description = IntentDescription("Resumes music playback in Aura Player.")
    // The video player can't start in an app Siri launched in the background, so bring the app up
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PlaybackManager.shared.resume()
        if let current = PlaybackManager.shared.currentTrack {
            return .result(dialog: "Playing \(current.title)")
        } else {
            return .result(dialog: "Resumed playback in Aura Player")
        }
    }
}

// MARK: - Pause Playback Intent
public struct PausePlaybackIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pause Playback"
    public static var description = IntentDescription("Pauses music playback in Aura Player.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PlaybackManager.shared.pause()
        return .result(dialog: "Paused Aura Player")
    }
}

// MARK: - Toggle Shuffle Intent
public struct ToggleShuffleIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Shuffle"
    public static var description = IntentDescription("Turns shuffle on or off in Aura Player.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PlaybackManager.shared.toggleShuffle()
        let status = PlaybackManager.shared.isShuffled ? "on" : "off"
        return .result(dialog: "Shuffle is now \(status)")
    }
}

// MARK: - What Is Playing Intent
public struct WhatIsPlayingIntent: AppIntent {
    public static var title: LocalizedStringResource = "What's Playing"
    public static var description = IntentDescription("Tells you the song currently playing in Aura Player.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if let current = PlaybackManager.shared.currentTrack {
            return .result(dialog: "Now playing \(current.title) by \(current.artist)")
        } else {
            return .result(dialog: "Nothing is currently playing in Aura Player")
        }
    }
}

// MARK: - Siri Shortcuts Provider
public struct AuraPlayerShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayNextTrackIntent(),
            phrases: [
                "Next song on \(.applicationName)",
                "Play next track on \(.applicationName)",
                "Skip song on \(.applicationName)",
                "Next in \(.applicationName)"
            ],
            shortTitle: "Next Song",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PlayPreviousTrackIntent(),
            phrases: [
                "Previous song on \(.applicationName)",
                "Play previous track on \(.applicationName)",
                "Previous in \(.applicationName)"
            ],
            shortTitle: "Previous Song",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Resume \(.applicationName)",
                "Resume music on \(.applicationName)"
            ],
            shortTitle: "Play Music",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause music on \(.applicationName)",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Pause Music",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ToggleShuffleIntent(),
            phrases: [
                "Shuffle \(.applicationName)",
                "Toggle shuffle on \(.applicationName)"
            ],
            shortTitle: "Toggle Shuffle",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: WhatIsPlayingIntent(),
            phrases: [
                "What's playing on \(.applicationName)",
                "What song is playing on \(.applicationName)"
            ],
            shortTitle: "What's Playing",
            systemImageName: "music.note"
        )
    }
}
