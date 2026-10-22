# 🌌 Aura Player - macOS Music & Video Player

A sleek, native macOS media player built with **SwiftUI** and **AVFoundation**, designed for ad-free high-resolution YouTube streaming and pristine local audio/video playback.

---

## ✨ Features

- **Default Video & Lyrics Resolution**: Automatically resolves the high-res video stream and synchronized lyrics for every song upon playback. Seamlessly switch between **Video (🎬)**, **Music (🎵)**, and **Lyrics (🎤)** at any time.
- **Smart Fisher-Yates Shuffle Algorithm**: Anti-clustering, non-repeating shuffle cycle that preserves your full listening history so pressing **Previous (⏮)** returns to the exact tracks in order.
- **Play Count Tracking & "Most Played"**: Tracks how many times you've listened to each song. Access the **"Most Played"** view in the sidebar to listen to your top tracks.
- **Singers & Artists Discovery**: Dedicated **"Singers & Artists" (🎙️)** section grouping all songs by singer with custom artist pages, play counts, and one-click "Play All" or "Shuffle".
- **Playlist Renaming & Merging**: Right-click any playlist to rename it or merge multiple playlists into one with automated duplicate detection.
- **Apple Music Library Extraction**: One-click import of all your Apple Music playlists (e.g. *Favourite Songs*, *Telugu Music*, *Hindi Music*, *English Music*, *Workout*, etc.). Extracted tracks play ad-free from YouTube or from local downloads.
- **Time-Synced Karaoke Lyrics**: Real-time time-synchronized lyrics that scroll and highlight the active line. Click any line to jump directly to that point in the song.
- **1000x1000 High-Res Album Artworks**: Automatically fetches official pristine 1000x1000 album artwork for Western and regional songs via Apple's official database, and extracts embedded ID3 artwork for local files.
- **High-Definition Video Mode**: Watch video songs in full resolution with native macOS **Picture-in-Picture (PiP)** and auto-hiding controls.
- **Ambient Glow Music Mode**: Enjoy music with an ambient background visualizer, album artwork, and real-time audio waveform animation.
- **Local Media Playback**: Drag and drop or browse local files (supports `.mp3`, `.m4a`, `.flac`, `.wav`, `.aac`, `.mp4`, `.mov`, `.mkv`).
- **Custom Playlists & Favorites**: Organize your favorite songs and videos into custom playlists with instant search filtering.
- **macOS System Integration**:
  - Control playback via keyboard media keys (`F7`, `F8`, `F9` / Touch Bar).
  - Track artwork and info in **macOS Control Center** and **Lock Screen** Now Playing.
  - Native Picture-in-Picture floating window.

---

## 🚀 How to Launch the App

You can launch the app immediately using Finder or Terminal:

### Option 1: Double-Click
Double-click `AuraPlayer.app` located at:
```
/Users/manikantaamara/Desktop/Antigravity/Player/AuraPlayer.app
```
*(You can also drag it into your `/Applications` folder for quick access via Spotlight or Launchpad).*

### Option 2: From Terminal
```bash
open /Users/manikantaamara/Desktop/Antigravity/Player/AuraPlayer.app
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`Space`** | Play / Pause |
| **`←` / `→`** | Seek backward / forward 5 seconds |
| **`⌘ + →`** | Next track |
| **`⌘ + ←`** | Previous track |
| **`⌘ + M`** | Mute / Unmute |

---

## 🛠 Rebuilding the App
If you make any changes to the Swift code, simply run:
```bash
cd /Users/manikantaamara/Desktop/Antigravity/Player
./build_app.sh
```
