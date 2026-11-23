import UIKit

/// Delete App's confirmation (plan §0.4), in the system's own alert, worded
/// as Springboard's second one is. Springboard (iOS 27 simulator) says:
///
/// > **Delete “CS”?**
/// > Deleting this app will also delete its data.
/// > [Cancel] [Delete]
///
/// Shelf's says the same, and what is different about Shelf's apps: the
/// data goes from every device, and nothing can bring it back. There's no
/// first alert (Springboard's "Remove “CS”?" with Remove from Home Screen),
/// since there's no App Library to keep an app in.
enum DeleteAlert {
    static func title(_ name: String) -> String {
        String(localized: "Delete “\(name)”?")
    }

    static let message = String(localized: "Deleting this app will also delete its data on all your devices. This can’t be undone.")

    /// Cancel on the left, Delete in red on the right, as Springboard's.
    @MainActor
    static func make(name: String, onDelete: @escaping @MainActor () -> Void,
                     onCancel: @escaping @MainActor () -> Void) -> UIAlertController {
        let alert = UIAlertController(title: title(name), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in onCancel() })
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { _ in onDelete() })
        return alert
    }
}

extension UIView {
    /// The view controller that can present over this view now: the one
    /// that owns it, or whatever that one is already presenting.
    var presenter: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder, !(next is UIViewController) { responder = next.next }
        guard var controller = responder as? UIViewController else { return nil }
        while let shown = controller.presentedViewController, !shown.isBeingDismissed { controller = shown }
        return controller
    }
}
