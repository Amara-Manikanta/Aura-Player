import SwiftUI

public struct AppleMusicImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: PlaylistStore
    @Bindable var playback: PlaybackManager
    
    @State private var playlists: [AppleMusicPlaylistInfo] = []
    @State private var isLoadingPlaylists: Bool = true
    @State private var importingPlaylistName: String?
    @State private var importedPlaylists: Set<String> = []
    @State private var errorMessage: String?
    
    public init(store: PlaylistStore, playback: PlaybackManager) {
        self.store = store
        self.playback = playback
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.title2)
                        .foregroundStyle(.pink)
                    Text("Import from Apple Music")
                        .font(.title3.bold())
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if isLoadingPlaylists {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Reading Apple Music Library...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Could not access Apple Music")
                        .font(.headline)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            } else if playlists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Playlists Found")
                        .font(.headline)
                    Text("Make sure the Apple Music app has playlists created.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(playlists) { pl in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color.pink.opacity(0.8), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                            Image(systemName: "music.note.list")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pl.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(pl.trackCount) songs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if importingPlaylistName == pl.name {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 80)
                        } else if importedPlaylists.contains(pl.name) {
                            Label("Imported", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                                .frame(width: 90)
                        } else {
                            Button("Import") {
                                importPlaylist(pl)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                            .controlSize(.small)
                            .frame(width: 80)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Imported tracks stream ad-free or play directly from local storage.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 500)
        .task {
            await loadPlaylists()
        }
    }
    
    private func loadPlaylists() async {
        isLoadingPlaylists = true
        errorMessage = nil
        do {
            let fetched = try await AppleMusicService.shared.fetchUserPlaylists()
            await MainActor.run {
                self.playlists = fetched
                self.isLoadingPlaylists = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoadingPlaylists = false
            }
        }
    }
    
    private func importPlaylist(_ pl: AppleMusicPlaylistInfo) {
        importingPlaylistName = pl.name
        Task {
            do {
                let tracks = try await AppleMusicService.shared.fetchTracks(forPlaylist: pl.name)
                await MainActor.run {
                    // Check if playlist already exists in AuraPlayer, or create it
                    if let existing = store.playlists.first(where: { $0.name == pl.name }) {
                        store.addTracks(tracks, to: existing.id)
                    } else {
                        let newPl = Playlist(
                            name: pl.name,
                            iconName: "music.note.list",
                            tracks: tracks,
                            isBuiltIn: false
                        )
                        store.playlists.append(newPl)
                        store.save()
                    }
                    
                    self.importedPlaylists.insert(pl.name)
                    self.importingPlaylistName = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import \(pl.name): \(error.localizedDescription)"
                    self.importingPlaylistName = nil
                }
            }
        }
    }
}
