import SwiftUI

public struct MergePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PlaylistStore
    public let sourcePlaylist: Playlist
    
    @State private var targetPlaylistId: UUID
    @State private var newPlaylistName: String = ""
    @State private var isCreatingNew: Bool = false
    @State private var skipDuplicates: Bool = true
    
    public init(store: PlaylistStore, sourcePlaylist: Playlist) {
        self.store = store
        self.sourcePlaylist = sourcePlaylist
        let firstOther = store.playlists.first(where: { $0.id != sourcePlaylist.id })?.id ?? UUID()
        self._targetPlaylistId = State(initialValue: firstOther)
        self._newPlaylistName = State(initialValue: "\(sourcePlaylist.name) + Merged")
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Merge \"\(sourcePlaylist.name)\"")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AuraTheme.textPrimary)
                        Text("\(sourcePlaylist.tracks.count) tracks in source")
                            .font(.system(size: 13))
                            .foregroundColor(AuraTheme.textSecondary)
                    }
                    .padding(.top, 16)
                    
                    VStack(spacing: 12) {
                        Picker("Destination", selection: $isCreatingNew) {
                            Text("Into Existing").tag(false)
                            Text("Create New").tag(true)
                        }
                        .pickerStyle(.segmented)
                        
                        if isCreatingNew {
                            TextField("New Playlist Name", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .liquidGlass(cornerRadius: 12)
                                .foregroundColor(AuraTheme.textPrimary)
                        } else {
                            Picker("Target Playlist", selection: $targetPlaylistId) {
                                ForEach(store.playlists.filter { $0.id != sourcePlaylist.id }) { pl in
                                    Text("\(pl.name) (\(pl.tracks.count) songs)").tag(pl.id)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                        }
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16)
                    
                    Toggle(isOn: $skipDuplicates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Skip Duplicates")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AuraTheme.textPrimary)
                            Text("Prevents adding songs that already exist in target")
                                .font(.system(size: 12))
                                .foregroundColor(AuraTheme.textTertiary)
                        }
                    }
                    .tint(AuraTheme.primary)
                    .padding(.horizontal, 8)
                    
                    Spacer()
                    
                    Button {
                        performMerge()
                    } label: {
                        Text("Merge Playlists")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AuraTheme.primaryGradient)
                            .cornerRadius(16)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Merge Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AuraTheme.textSecondary)
                }
            }
        }
    }
    
    private func performMerge() {
        if isCreatingNew {
            let target = store.createPlaylist(name: newPlaylistName)
            for track in sourcePlaylist.tracks {
                store.addTrack(track, to: target.id)
            }
        } else {
            for track in sourcePlaylist.tracks {
                store.addTrack(track, to: targetPlaylistId)
            }
        }
        Haptics.success()
        dismiss()
    }
}
