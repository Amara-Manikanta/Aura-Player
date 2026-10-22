import SwiftUI

/// One place to find music: picks from your taste, new songs for you, and all new releases.
public struct DiscoverView: View {
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    enum Tab: String, CaseIterable {
        case picks = "Top Picks"
        case newForYou = "New for You"
        case newReleases = "New Releases"
        
        var icon: String {
            switch self {
            case .picks: return "wand.and.stars"
            case .newForYou: return "sparkles"
            case .newReleases: return "calendar.badge.clock"
            }
        }
    }
    @AppStorage("discoverTab") private var tab: Tab = .picks
    
    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Discover").font(.system(size: 26, weight: .bold))
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 380)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .background(.ultraThinMaterial)
            
            switch tab {
            case .picks:
                ForYouView(store: store, playback: playback, section: .picks, embedded: true).id(Tab.picks)
            case .newForYou:
                ForYouView(store: store, playback: playback, section: .new, embedded: true).id(Tab.newForYou)
            case .newReleases:
                NewReleasesView(store: store, playback: playback, embedded: true)
            }
        }
    }
}
