import SwiftUI
import AppKit

/// Shows the pairing code the iPhone needs, and when the last sync happened
struct SyncWindowView: View {
    @State private var server = SyncServer.shared
    
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 40))
                .foregroundStyle(.purple)
            
            Text("Sync with iPhone")
                .font(.title2.bold())
            
            Text("On your iPhone: Settings ▸ Sync with Mac, then enter this code. Both need to be on the same Wi-Fi.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Text(server.code)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .tracking(6)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            
            HStack(spacing: 10) {
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.code, forType: .string)
                }
                Button("New Code") { server.renewCode() }
                    .help("Phones that were paired have to enter the new code")
            }
            
            Divider()
            
            VStack(spacing: 4) {
                Label(server.status, systemImage: server.isRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(server.isRunning ? .green : .orange)
                if let last = server.lastSync {
                    Text("Last synced \(last.formatted(.relative(presentation: .named)))" + (server.lastDevice.map { " with \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("If macOS asks whether Aura Player may accept incoming connections, choose Allow.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 400)
    }
}

/// Sync ▸ iPhone Sync…
struct OpenSyncWindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("iPhone Sync…") { openWindow(id: "iphone-sync") }
    }
}
