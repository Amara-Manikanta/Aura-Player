import UIKit

/// Opens the iOS share sheet (WhatsApp, Messages, ...). It has to be shown from the screen that is on top: a song
/// shared from the full player or from a sheet was silently dropped when it was presented from the app's root screen,
/// which is already covered by that sheet.
enum ShareSheet {
    @MainActor
    static func present(text: String) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // iPad needs an anchor; harmless on iPhone
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(controller, animated: true)
    }
}
