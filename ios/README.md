# 🌌 Aura Player for iPhone (iOS)

A sleek, native iOS media player built with **SwiftUI**, **AVFoundation**, and **WebKit**, featuring synchronized karaoke lyrics, YouTube video streaming with Picture-in-Picture (PiP), high-resolution album artwork, and background audio.

---

## ✨ Features

- **Modern Apple Music & Echo Aesthetic**:
  - Deep AMOLED black (`#0D0D11`) and translucent glassmorphism surfaces (`.ultraThinMaterial`).
  - Dynamic ambient gradient glow that matches the active track's vibes.
  - Floating pill **MiniPlayer** docked right above the tab bar with interactive scrub bar.
  - Interactive **Full Player (Now Playing)** sheet with artwork scaling animation on play/pause.

- **Audio, Video, and Lyrics Modes**:
  - **Audio (🎵)**: Clean album artwork with spring physics, full scrubber, and volume controls.
  - **Video (🎬)**: HD YouTube streaming with **Picture-in-Picture (PiP)**, full-screen mode, and AirPlay.
  - **Lyrics (🎤)**: Real-time time-synchronized karaoke lyrics powered by LRCLib. Active lyric lines scale up, glow, and auto-scroll. Tap any lyric line to jump directly to that point in the song!

- **Search & YouTube Integration**:
  - Live YouTube search for songs, artists, or direct YouTube links.
  - One-tap playback or "Add to Playlist" directly from search results.
  - Intelligent `MetadataCleaner` regex engine that strips junk like `(Official Video)` or `- Topic` for maximum lyrics and artwork hit rates.

- **Library & Custom Playlists**:
  - Built-in **Favorites** and **Most Played** tracking.
  - Create, customize, and manage personal playlists on the go.
  - Clean dropdown menus (`...`) for quick queueing and playlist additions.

- **iOS System Integration**:
  - **Background Audio**: Music keeps playing when you switch apps or lock your phone (`AVAudioSessionCategoryPlayback`).
  - **Lock Screen & Control Center**: Full media controls, scrub bar, and retina artwork via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.

---

## 🚀 Running the App

### Option 1: In Xcode
1. The project is located at:
   ```
   /Users/manikantaamara/Desktop/Antigravity/AuraPlayerIOS/AuraPlayerIOS.xcodeproj
   ```
2. Select your device (iPhone Simulator or your tethered physical iPhone) in the top scheme bar.
3. Press **`⌘ + R`** (or click the Play button) to build and run.

### Option 2: Command Line (Simulator)
```bash
cd /Users/manikantaamara/Desktop/Antigravity/AuraPlayerIOS
xcodebuild -scheme AuraPlayerIOS -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/AuraPlayerIOS* -name "AuraPlayerIOS.app" | head -n 1)
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted com.antigravity.auraplayer
```

---

## 📱 Installing on Your Physical iPhone
1. Connect your iPhone to this Mac via USB cable.
2. In Xcode, open `AuraPlayerIOS.xcodeproj`.
3. In the project settings under **Signing & Capabilities**, select your personal **Team** (your standard Apple ID).
4. Choose your physical iPhone from the device selector at the top.
5. Press **`⌘ + R`** to install directly to your phone!
