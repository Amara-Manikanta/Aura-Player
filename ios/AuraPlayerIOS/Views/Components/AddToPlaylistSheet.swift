import SwiftUI

public struct AddToPlaylistSheet: View {
    public let track: MediaTrack
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPlaylistName: String = ""
    @State private var isCreatingNew: Bool = false
    
    public init(track: MediaTrack, playlistStore: PlaylistStore) {
        self.track = track
        self.playlistStore = playlistStore
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraTheme.backgroundDark.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Track header summary
                    HStack(spacing: 12) {
                        if let thumb = track.thumbnailURL, let url = URL(string: thumb) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AuraTheme.surfaceElevated)
                                        .frame(width: 48, height: 48)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 13))
                                .foregroundColor(AuraTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Divider().overlay(AuraTheme.glassBorder)
                    
                    // New playlist inline row
                    if isCreatingNew {
                        HStack {
                            TextField("Playlist Name", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(AuraTheme.surfaceElevated)
                                .cornerRadius(10)
                                .foregroundColor(AuraTheme.textPrimary)
                            
                            Button("Create & Add") {
                                guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                let created = playlistStore.createPlaylist(name: newPlaylistName)
                                playlistStore.addTrack(track, to: created.id)
                                Haptics.success()
                                dismiss()
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AuraTheme.primary)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        Button {
                            withAnimation(.spring()) { isCreatingNew = true }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AuraTheme.primary)
                                    .font(.system(size: 20))
                                Text("New Playlist")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AuraTheme.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Existing playlists
                    List {
                        ForEach(playlistStore.playlists) { pl in
                            Button {
                                playlistStore.addTrack(track, to: pl.id)
                                Haptics.success()
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: pl.iconName)
                                        .font(.system(size: 18))
                                        .foregroundColor(AuraTheme.primary)
                                        .frame(width: 32, height: 32)
                                        .background(AuraTheme.primary.opacity(0.15))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(AuraTheme.textPrimary)
                                        Text("\(pl.tracks.count) tracks")
                                            .font(.system(size: 12))
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AuraTheme.surfaceCard)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AuraTheme.primary)
                }
            }
        }
    }
}
