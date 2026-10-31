import SwiftUI
import UIKit

@main
struct AuraPlayerIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
        // Like the Mac app: pick up Apple Music play counts / new songs at launch and on return
        // (at most every 10 minutes, and only after access was allowed from Settings)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await AppleMusicSync.shared.autoSync() }
                Task { await MacSyncClient.shared.autoSync() }
            }
        }
    }
}

/// The app is portrait-only, except the full-screen video, which switches to landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
    
    /// Allows `mask` and rotates the screen to `preferred` (e.g. landscape for full-screen video).
    static func set(_ newMask: UIInterfaceOrientationMask, rotateTo preferred: UIInterfaceOrientationMask) {
        mask = newMask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        // The screen on top (e.g. the full-screen cover) decides which orientations are allowed
        var top = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        requestRotation(scene: scene, to: preferred, attemptsLeft: 5)
    }
    
    /// UIKit only accepts the rotation once the new screen (e.g. the full-screen cover) has finished
    /// presenting and reported the orientations it allows, so retry briefly until it does.
    private static func requestRotation(scene: UIWindowScene, to preferred: UIInterfaceOrientationMask, attemptsLeft: Int) {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: preferred)) { error in
            guard attemptsLeft > 1 else {
                NSLog("AuraPlayer orientation request failed: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                requestRotation(scene: scene, to: preferred, attemptsLeft: attemptsLeft - 1)
            }
        }
    }
}
