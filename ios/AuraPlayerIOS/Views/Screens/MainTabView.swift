import SwiftUI

public struct MainTabView: View {
    @StateObject private var playlistStore = PlaylistStore.shared
    @StateObject private var playback = PlaybackManager.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Background Web Player Host (keeps audio active across all tabs & audio mode)
            if !showFullPlayer {
                YouTubeWebPlayerView(playback: playback)
                    .frame(width: 160, height: 90)
                    .opacity(0.05)
                    .allowsHitTesting(false)
                    .zIndex(-100)
            }
            
            TabView(selection: $selectedTab) {
                HomeView(playlistStore: playlistStore, playback: playback)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                ForYouView(store: playlistStore, playback: playback)
                    .tabItem {
                        Label("For You", systemImage: "sparkles")
                    }
                    .tag(1)
                
                SearchView(playlistStore: playlistStore, playback: playback)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)
                
                LibraryView(playlistStore: playlistStore, playback: playback)
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(3)
            }
            .tint(AuraTheme.primary)
            
            // Floating MiniPlayer docked above Tab Bar
            if playback.currentTrack != nil {
                MiniPlayerView(playback: playback) {
                    showFullPlayer = true
                }
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerSheet(playback: playback, playlistStore: playlistStore)
        }
        .preferredColorScheme(.dark)
    }
}
