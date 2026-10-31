import SwiftUI

/// The playing position, kept apart from the rest of the player state: it changes four times a second,
/// and anything watching `PlaybackManager` itself would redraw its whole screen that often.
/// Only views that show the time (progress bars, time labels) watch this.
public final class PlaybackClock: ObservableObject {
    @Published public var time: TimeInterval = 0
}

/// Redraws only its content as the playing position moves
struct ClockObserver<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    let content: (TimeInterval) -> Content
    
    init(_ clock: PlaybackClock, @ViewBuilder content: @escaping (TimeInterval) -> Content) {
        self.clock = clock
        self.content = content
    }
    
    var body: some View { content(clock.time) }
}
