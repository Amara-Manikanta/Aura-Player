import SwiftUI

public struct MergePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: PlaylistStore
    let sourcePlaylist: Playlist
    var onMerged: ((UUID) -> Void)? = nil
    
    enum MergeMode: String, CaseIterable {
        case intoExisting = "Into Existing Playlist"
        case createNew = "Create New Playlist"
    }
    
    @State private var mergeMode: MergeMode = .intoExisting
    @State private var targetPlaylistId: UUID
    @State private var selectedAdditionalIds: Set<UUID> = []
    @State private var newPlaylistName: String
    @State private var skipDuplicates: Bool = true
    @State private var deleteSource: Bool = true
    @State private var isProcessing: Bool = false
    
    public init(
        store: PlaylistStore,
        sourcePlaylist: Playlist,
        onMerged: ((UUID) -> Void)? = nil
    ) {
        self.store = store
        self.sourcePlaylist = sourcePlaylist
        self.onMerged = onMerged
        
        // Pick best default target playlist (prefer user custom playlists)
        let candidates = store.playlists.filter { $0.id != sourcePlaylist.id }
        let userCandidate = candidates.first(where: { !$0.isBuiltIn }) ?? candidates.first
        self._targetPlaylistId = State(initialValue: userCandidate?.id ?? UUID())
        self._newPlaylistName = State(initialValue: "\(sourcePlaylist.name) + Merged")
    }
    
    private var availableTargets: [Playlist] {
        store.playlists.filter { $0.id != sourcePlaylist.id }
    }
    
    private var selectedTargetPlaylist: Playlist? {
        store.playlists.first(where: { $0.id == targetPlaylistId })
    }
    
    // Live calculation for existing target
    private var previewExistingStats: (added: Int, skipped: Int, totalAfter: Int) {
        guard let target = selectedTargetPlaylist else { return (0, 0, 0) }
        
        func normalizedKey(_ track: MediaTrack) -> String {
            let t = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let a = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(t)|\(a)"
        }
        
        var existingKeys = Set(target.tracks.map { normalizedKey($0) })
        var existingURLs = Set(target.tracks.map { $0.originalURL.lowercased() })
        
        var added = 0
        var skipped = 0
        
        for track in sourcePlaylist.tracks {
            let key = normalizedKey(track)
            let urlKey = track.originalURL.lowercased()
            let isDup = (!urlKey.isEmpty && existingURLs.contains(urlKey)) ||
                        (!track.title.isEmpty && existingKeys.contains(key))
            
            if skipDuplicates && isDup {
                skipped += 1
            } else {
                added += 1
                if !urlKey.isEmpty { existingURLs.insert(urlKey) }
                if !track.title.isEmpty { existingKeys.insert(key) }
            }
        }
        
        return (added, skipped, target.tracks.count + added)
    }
    
    // Live calculation for new merged playlist
    private var previewNewPlaylistStats: (totalTracks: Int, skippedDups: Int) {
        let allIds = [sourcePlaylist.id] + Array(selectedAdditionalIds)
        
        func normalizedKey(_ track: MediaTrack) -> String {
            let t = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let a = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(t)|\(a)"
        }
        
        var existingKeys = Set<String>()
        var existingURLs = Set<String>()
        var total = 0
        var dups = 0
        
        for id in allIds {
            guard let pl = store.playlists.first(where: { $0.id == id }) else { continue }
            for track in pl.tracks {
                let key = normalizedKey(track)
                let urlKey = track.originalURL.lowercased()
                let isDup = (!urlKey.isEmpty && existingURLs.contains(urlKey)) ||
                            (!track.title.isEmpty && existingKeys.contains(key))
                
                if skipDuplicates && isDup {
                    dups += 1
                } else {
                    total += 1
                    if !urlKey.isEmpty { existingURLs.insert(urlKey) }
                    if !track.title.isEmpty { existingKeys.insert(key) }
                }
            }
        }
        
        return (total, dups)
    }
    
    private var canMerge: Bool {
        if isProcessing { return false }
        switch mergeMode {
        case .intoExisting:
            return selectedTargetPlaylist != nil
        case .createNew:
            return !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.purple)
                    }
                    Text("Merge Playlists")
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
            .padding(16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Source Card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOURCE PLAYLIST")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Image(systemName: sourcePlaylist.iconName)
                                .font(.system(size: 26))
                                .foregroundStyle(.purple)
                                .frame(width: 38, height: 38)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sourcePlaylist.name)
                                    .font(.headline)
                                Text("\(sourcePlaylist.tracks.count) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    
                    // Mode Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MERGE DESTINATION")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $mergeMode) {
                            ForEach(MergeMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Destination Content
                    if mergeMode == .intoExisting {
                        destinationExistingView
                    } else {
                        destinationCreateNewView
                    }
                    
                    // Options
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OPTIONS")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        Toggle("Skip duplicate songs (by name & artist)", isOn: $skipDuplicates)
                            .font(.subheadline)
                        
                        if !sourcePlaylist.isBuiltIn {
                            Toggle(
                                mergeMode == .intoExisting
                                    ? "Delete source playlist \"\(sourcePlaylist.name)\" after merging"
                                    : "Delete selected source playlist(s) after creating new playlist",
                                isOn: $deleteSource
                            )
                            .font(.subheadline)
                            .foregroundStyle(deleteSource ? .red : .primary)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    performMerge()
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(mergeMode == .intoExisting ? "Merge Into Playlist" : "Create Combined Playlist")
                            .bold()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(canMerge ? LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canMerge)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 530)
    }
    
    // Subview: Merge into existing playlist
    private var destinationExistingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableTargets.isEmpty {
                Text("No other playlists available to merge into.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select Target Playlist:")
                        .font(.subheadline.bold())
                    
                    Picker("Target Playlist", selection: $targetPlaylistId) {
                        ForEach(availableTargets) { pl in
                            Text("\(pl.name) (\(pl.tracks.count) tracks)").tag(pl.id)
                        }
                    }
                    .labelsHidden()
                }
                
                // Live preview badge
                let stats = previewExistingStats
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stats.added) new tracks will be added")
                            .font(.subheadline.bold())
                        if stats.skipped > 0 {
                            Text("\(stats.skipped) duplicate tracks skipped • Target will have \(stats.totalAfter) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Target will have \(stats.totalAfter) tracks total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // Subview: Create new merged playlist
    private var destinationCreateNewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Playlist Name:")
                    .font(.subheadline.bold())
                TextField("e.g. My Favorites & Mix", text: $newPlaylistName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Select other playlists to combine with \"\(sourcePlaylist.name)\":")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(availableTargets) { pl in
                            Button {
                                if selectedAdditionalIds.contains(pl.id) {
                                    selectedAdditionalIds.remove(pl.id)
                                } else {
                                    selectedAdditionalIds.insert(pl.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedAdditionalIds.contains(pl.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedAdditionalIds.contains(pl.id) ? .purple : .secondary)
                                    Image(systemName: pl.iconName)
                                        .foregroundStyle(.secondary)
                                    Text(pl.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(pl.tracks.count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedAdditionalIds.contains(pl.id) ? Color.purple.opacity(0.12) : Color.white.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            
            // Live preview
            let stats = previewNewPlaylistStats
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Result: \(stats.totalTracks) combined tracks")
                        .font(.subheadline.bold())
                    if stats.skippedDups > 0 {
                        Text("\(stats.skippedDups) duplicate tracks skipped across playlists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func performMerge() {
        guard canMerge else { return }
        isProcessing = true
        
        // Capture everything up front, dismiss the sheet, then mutate the store on the next
        // run-loop turn. Mutating (and possibly deleting the source playlist) while the sheet
        // and its presenting view are still rendering tears down views mid-update.
        let store = store
        let onMerged = onMerged
        let sourceId = sourcePlaylist.id
        let skipDuplicates = skipDuplicates
        let deleteSource = deleteSource
        let mode = mergeMode
        let targetId = targetPlaylistId
        let additionalIds = Array(selectedAdditionalIds)
        let name = newPlaylistName
        
        dismiss()
        
        Task { @MainActor in
            switch mode {
            case .intoExisting:
                store.mergePlaylists(
                    sourceId: sourceId,
                    targetId: targetId,
                    skipDuplicates: skipDuplicates,
                    deleteSource: deleteSource
                )
                onMerged?(targetId)
                
            case .createNew:
                if let newId = store.createMergedPlaylist(
                    name: name,
                    sourceIds: [sourceId] + additionalIds,
                    skipDuplicates: skipDuplicates,
                    deleteSources: deleteSource
                ) {
                    onMerged?(newId)
                }
            }
        }
    }
}
