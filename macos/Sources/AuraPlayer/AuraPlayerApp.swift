import SwiftUI
import AppKit

@main
struct AuraPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// For Indian film songs, play the version in this language when one exists
    @AppStorage("preferredLanguage") private var preferredLanguage = "Telugu"
    @AppStorage("showVisualizer") private var showVisualizer = true
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 750)
                .background(.ultraThinMaterial)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Playback") {
                // Space, ⌘← / ⌘→ and ← / → are handled app-wide in AppDelegate's key monitor
                Button("Play / Pause (Space)") {
                    PlaybackManager.shared.togglePlayPause()
                }
                
                Button("Next Track") {
                    PlaybackManager.shared.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                
                Button("Previous Track") {
                    PlaybackManager.shared.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                
                Divider()
                
                Picker("Preferred Song Language", selection: $preferredLanguage) {
                    Text("Original (no preference)").tag("None")
                    Divider()
                    ForEach(["Telugu", "Tamil", "Hindi", "Kannada", "Malayalam"], id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                
                Divider()
                
                Button("Toggle Mute") {
                    PlaybackManager.shared.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [.command])
                
                Divider()
                
                OpenMiniPlayerCommand()
                Toggle("Show Visualizer", isOn: $showVisualizer)
            }
            
            CommandMenu("Sync") {
                OpenSyncWindowCommand()
            }
        }
        
        // Small floating player that stays above other apps
        Window("Mini Player", id: "mini-player") {
            MiniPlayerView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)   // drag any edge to resize
        .defaultSize(width: 400, height: 330)
        .defaultPosition(.topTrailing)
        
        // Pairing code and status for syncing with the iPhone
        Window("iPhone Sync", id: "iphone-sync") {
            SyncWindowView()
        }
        .windowResizability(.contentSize)
        
        // Player in the macOS menu bar
        MenuBarExtra {
            MenuBarPlayerView()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Playback ▸ Mini Player (⇧⌘M)
struct OpenMiniPlayerCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Mini Player") { openWindow(id: "mini-player") }
            .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var mediaKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UserDefaults.standard.register(defaults: ["preferredLanguage": "Telugu"])
        installKeyboardShortcuts()
    }
    
    /// Playback shortcuts that work wherever focus is (song list, video, sidebar), except
    /// while typing in a text field. Handled here instead of via SwiftUI because plain-key
    /// menu shortcuts and onKeyPress only fire when particular views have focus.
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isTyping = NSApp.keyWindow?.firstResponder is NSText
            let playback = PlaybackManager.shared
            
            switch (event.keyCode, mods) {
            case (49, []) where !isTyping:                 // Space
                playback.togglePlayPause()
            case (124, [.command]), (124, [.command, .numericPad, .function]):  // ⌘→
                playback.next()
            case (123, [.command]), (123, [.command, .numericPad, .function]):  // ⌘←
                playback.previous()
            case (124, _) where !isTyping && !mods.contains(.command) && !mods.contains(.option) && !mods.contains(.shift):  // →
                playback.seek(to: playback.currentTime + 5)
            case (123, _) where !isTyping && !mods.contains(.command) && !mods.contains(.option) && !mods.contains(.shift):  // ←
                playback.seek(to: max(0, playback.currentTime - 5))
            // F7 / F8 / F9 / F10 when "Use F1, F2, etc. keys as standard function keys" is on
            case (98, _):  playback.previous()        // F7  ⏮
            case (100, _): playback.togglePlayPause() // F8  ⏯
            case (101, _): playback.next()            // F9  ⏭
            case (109, _): playback.toggleMute()      // F10 🔇
            default:
                if mods.contains(.function) {
                    AppLog.log("keys", "unhandled function key keyCode \(event.keyCode)")
                }
                return event
            }
            AppLog.log("keys", "handled keyCode \(event.keyCode)")
            return nil // consumed, so the video player / list doesn't also react
        }
        
        // Hardware media keys (⏮ ⏯ ⏭ on F7–F9) when they reach the app as system events
        // instead of through Now Playing (e.g. while the web video player holds Now Playing)
        mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            guard event.subtype.rawValue == 8 else { return event }
            let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
            let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA
            guard isDown else { return event }
            let playback = PlaybackManager.shared
            switch keyCode {
            case 16: playback.togglePlayPause()   // NX_KEYTYPE_PLAY
            case 17, 19: playback.next()          // NX_KEYTYPE_NEXT / FAST
            case 18, 20: playback.previous()      // NX_KEYTYPE_PREVIOUS / REWIND
            case 7: playback.toggleMute()         // NX_KEYTYPE_MUTE
            default: return event
            }
            AppLog.log("keys", "media key event \(keyCode)")
            return nil
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
