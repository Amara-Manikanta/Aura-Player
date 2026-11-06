import SwiftUI

public struct MainTabView: View {
    @StateObject private var playlistStore = PlaylistStore.shared
    @StateObject private var playback = PlaybackManager.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    
    public init() {}
    
    private var noticeBinding: Binding<Bool> {
        Binding(get: { playlistStore.importNotice != nil }, set: { if !$0 { playlistStore.importNotice = nil } })
    }
    
    /// Room for the floating mini player, so lists can scroll their last rows into view
    private var miniPlayerSpace: CGFloat { playback.currentTrack != nil ? 76 : 0 }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Background Web Player Host (keeps audio active across all tabs & audio mode)
            // Tucked invisibly behind tabs: non-zero size and minimal opacity keeps WebKit playing without visual bleed
            YouTubeWebPlayerView(playback: playback, hostID: "background")
                .frame(width: 2, height: 2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .zIndex(-100)
            
            TabView(selection: $selectedTab) {
                HomeView(playlistStore: playlistStore, playback: playback)
                    .safeAreaPadding(.bottom, miniPlayerSpace)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                ForYouView(store: playlistStore, playback: playback)
                    .safeAreaPadding(.bottom, miniPlayerSpace)
                    .tabItem {
                        Label("For You", systemImage: "sparkles")
                    }
                    .tag(1)
                
                SearchView(playlistStore: playlistStore, playback: playback)
                    .safeAreaPadding(.bottom, miniPlayerSpace)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)
                
                LibraryView(playlistStore: playlistStore, playback: playback)
                    .safeAreaPadding(.bottom, miniPlayerSpace)
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
        // Stay docked at the bottom when the keyboard opens (it used to ride up and cover search fields)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerSheet(playback: playback, playlistStore: playlistStore)
                .buttonStyle(AuraPlainButtonStyle())
        }
        // Every screen and sheet opened from here: iOS "Button Shapes" would otherwise draw a round shape behind
        // each button and make icon rows wider than the screen
        .buttonStyle(AuraPlainButtonStyle())
        .alert("Import", isPresented: noticeBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playlistStore.importNotice ?? "")
        }
        .preferredColorScheme(.dark)
    }
}
