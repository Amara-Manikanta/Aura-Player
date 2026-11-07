import SwiftUI

/// "Rename Song" for any list of songs: set `track` to the song to rename and this asks for the new name and artist.
/// The new name is saved on every copy of the song and, if it is playing, shown straight away.
private struct RenameSongAlert: ViewModifier {
    let store: PlaylistStore
    let playback: PlaybackManager
    @Binding var track: MediaTrack?
    @State private var title = ""
    @State private var artist = ""
    
    func body(content: Content) -> some View {
        content
            .onChange(of: track) { _, new in
                title = new?.title ?? ""
                artist = new?.artist ?? ""
            }
            .alert("Rename Song", isPresented: Binding(get: { track != nil }, set: { if !$0 { track = nil } })) {
                TextField("Song Title", text: $title)
                TextField("Artist", text: $artist)
                Button("Save") {
                    if let t = track {
                        let newTitle = title.trimmingCharacters(in: .whitespaces)
                        if !newTitle.isEmpty {
                            let newArtist = artist.trimmingCharacters(in: .whitespaces)
                            let finalArtist = newArtist.isEmpty ? "Unknown Artist" : newArtist
                            store.renameSong(t, title: newTitle, artist: finalArtist)
                            playback.applyRename(to: t.id, title: newTitle, artist: finalArtist)
                        }
                    }
                    track = nil
                }
                Button("Cancel", role: .cancel) { track = nil }
            }
    }
}

extension View {
    func renameSongAlert(track: Binding<MediaTrack?>, store: PlaylistStore, playback: PlaybackManager) -> some View {
        modifier(RenameSongAlert(store: store, playback: playback, track: track))
    }
}
