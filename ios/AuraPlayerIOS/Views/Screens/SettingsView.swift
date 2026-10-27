import SwiftUI

public struct SettingsView: View {
    @ObservedObject var playlistStore: PlaylistStore
    @AppStorage("playerTheme") private var playerTheme: PlayerTheme = .modern
    @AppStorage("sansaHaptics") private var sansaHaptics: Bool = true
    @AppStorage("sansaWheelDefault") private var sansaWheelDefault: String = "seek"
    @Environment(\.dismiss) private var dismiss
    
    @State private var showFileImporter: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var statusToast: String?
    @ObservedObject private var appleMusic = AppleMusicSync.shared
    
    public init(playlistStore: PlaylistStore) {
        self.playlistStore = playlistStore
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section 1: Player Themes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PLAYER THEME")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AuraTheme.textTertiary)
                                .tracking(1)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 12) {
                                ForEach(PlayerTheme.allCases) { theme in
                                    let isSelected = (playerTheme == theme)
                                    Button {
                                        Haptics.medium()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            playerTheme = theme
                                        }
                                    } label: {
                                        HStack(spacing: 14) {
                                            // Theme Icon Badge
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(
                                                        theme == .modern
                                                            ? AuraTheme.primaryGradient
                                                            : SansaTheme.neonBlueGradient
                                                    )
                                                    .frame(width: 52, height: 52)
                                                    .shadow(
                                                        color: (theme == .modern ? AuraTheme.primary : SansaTheme.neonBlue).opacity(isSelected ? 0.6 : 0.2),
                                                        radius: 10
                                                    )
                                                
                                                Image(systemName: theme.iconName)
                                                    .font(.system(size: 22, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            // Info
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack {
                                                    Text(theme.rawValue)
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(.white)
                                                    
                                                    if theme == .sansa {
                                                        Text("RETRO")
                                                            .font(.system(size: 9, weight: .black))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(SansaTheme.neonBlue.opacity(0.2))
                                                            .foregroundColor(SansaTheme.neonBlue)
                                                            .clipShape(Capsule())
                                                    }
                                                }
                                                
                                                Text(theme.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AuraTheme.textSecondary)
                                                    .lineLimit(2)
                                            }
                                            
                                            Spacer()
                                            
                                            // Selection Radio Mark
                                            ZStack {
                                                Circle()
                                                    .stroke(isSelected ? (theme == .modern ? AuraTheme.primary : SansaTheme.neonBlue) : AuraTheme.glassBorder, lineWidth: 2)
                                                    .frame(width: 24, height: 24)
                                                
                                                if isSelected {
                                                    Circle()
                                                        .fill(theme == .modern ? AuraTheme.primary : SansaTheme.neonBlue)
                                                        .frame(width: 14, height: 14)
                                                }
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18)
                                                .fill(isSelected ? AuraTheme.surfaceElevated : AuraTheme.surfaceCard)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(
                                                    isSelected
                                                        ? (theme == .modern ? AuraTheme.primary : SansaTheme.neonBlue).opacity(0.8)
                                                        : AuraTheme.glassBorder,
                                                    lineWidth: isSelected ? 1.5 : 1
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        
                        // Section 2: Sansa Retro Settings
                        if playerTheme == .sansa {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SANSA e260 ROTATOR SETTINGS")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AuraTheme.textTertiary)
                                    .tracking(1)
                                    .padding(.horizontal, 4)
                                
                                VStack(spacing: 8) {
                                    // Default Wheel Action
                                    HStack {
                                        Label("Default Wheel Mode", systemImage: "dial.low.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Picker("Default Wheel Mode", selection: $sansaWheelDefault) {
                                            Text("Scrub Time").tag("seek")
                                            Text("Volume").tag("volume")
                                        }
                                        .pickerStyle(.menu)
                                        .tint(SansaTheme.neonBlue)
                                    }
                                    .padding(14)
                                    .liquidGlass(cornerRadius: 14)
                                    
                                    // Mechanical Haptic Ticks
                                    Toggle(isOn: $sansaHaptics) {
                                        Label("Mechanical Haptic Ticks", systemImage: "iphone.radiowaves.left.and.right")
                                            .foregroundColor(.white)
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .tint(SansaTheme.neonBlue)
                                    .padding(14)
                                    .liquidGlass(cornerRadius: 14)
                                }
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                        
                        // Section 3: Library & Data
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LIBRARY & STORAGE")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AuraTheme.textTertiary)
                                .tracking(1)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 8) {
                                // Stats Row
                                HStack {
                                    Label("Catalog Statistics", systemImage: "music.note.list")
                                        .foregroundColor(.white)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text("\(playlistStore.playlists.count) playlists • \(playlistStore.allUniqueTracks.count) songs")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(AuraTheme.textSecondary)
                                }
                                .padding(14)
                                .liquidGlass(cornerRadius: 14)
                                
                                // Apple Music: play counts, Recently Added and new songs from this iPhone's library
                                Button {
                                    Task { statusToast = await appleMusic.syncNow() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Label("Sync with Apple Music", systemImage: "music.note.house")
                                                .foregroundColor(.white)
                                                .font(.system(size: 15, weight: .semibold))
                                            Text(appleMusic.lastSync.map { "Play counts, Recently Added & new songs • synced \($0.formatted(.relative(presentation: .named)))" }
                                                 ?? "Play counts, Recently Added & new songs from this iPhone")
                                                .font(.system(size: 11))
                                                .foregroundColor(AuraTheme.textTertiary)
                                        }
                                        Spacer()
                                        if appleMusic.isSyncing {
                                            ProgressView().tint(AuraTheme.primary)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .foregroundColor(AuraTheme.primary)
                                        }
                                    }
                                    .padding(14)
                                    .liquidGlass(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                                .disabled(appleMusic.isSyncing)
                                
                                // Export Backup
                                if let backupURL = playlistStore.createBackupFileURL() {
                                    ShareLink(
                                        item: backupURL,
                                        preview: SharePreview("AuraPlayer Library Backup", icon: Image(systemName: "arrow.down.doc.fill"))
                                    ) {
                                        HStack {
                                            Label("Export Library Backup", systemImage: "square.and.arrow.up")
                                                .foregroundColor(.white)
                                                .font(.system(size: 15, weight: .semibold))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(AuraTheme.textTertiary)
                                        }
                                        .padding(14)
                                        .liquidGlass(cornerRadius: 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Import Backup
                                Button {
                                    showFileImporter = true
                                } label: {
                                    HStack {
                                        Label("Import Backup from Files", systemImage: "square.and.arrow.down")
                                            .foregroundColor(.white)
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(14)
                                    .liquidGlass(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                                
                                // Reset to Bundled Library
                                Button {
                                    showResetConfirmation = true
                                } label: {
                                    HStack {
                                        Label("Restore Original macOS Library", systemImage: "arrow.counterclockwise.circle")
                                            .foregroundColor(Color.orange)
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(AuraTheme.textTertiary)
                                    }
                                    .padding(14)
                                    .liquidGlass(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Status Toast
                        if let toast = statusToast {
                            Text(toast)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AuraTheme.primary)
                                .padding(.horizontal, 20)
                        }
                        
                        // Section 4: About
                        VStack(alignment: .center, spacing: 6) {
                            Text("Aura Player v2.2")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("Multi-Platform Music Ecosystem (iOS • macOS • Android)")
                                .font(.system(size: 12))
                                .foregroundColor(AuraTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AuraTheme.primary)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        let ok = playlistStore.importBackup(from: first)
                        statusToast = ok ? "Library restored successfully!" : "Failed to parse backup JSON."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                    }
                case .failure(let err):
                    statusToast = "Error picking file: \(err.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                }
            }
            .confirmationDialog(
                "Restore Original Library?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore All 17 Playlists (3,432 tracks)", role: .destructive) {
                    playlistStore.resetToBundled()
                    statusToast = "Restored all 17 playlists and 3,432 tracks!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusToast = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
