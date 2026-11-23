import SwiftUI
import UIKit

/// Shelf's own ask, before iOS's: "Run Tracker wants to use your location",
/// with the app's icon, what allowing it lets the app do, Allow and Don't
/// Allow. Plain and short, as iOS's own permission alerts are.
struct PermissionSheet: View {
    var capability: Capability
    var app: AppMeta
    /// iOS's prompt follows an Allow, and the sheet says so.
    var systemWillAsk: Bool
    var answer: (PermissionChoice) -> Void

    var body: some View {
        VStack(spacing: PermissionMetrics.spacing) {
            IconImage(face: IconFace(app), size: PermissionMetrics.iconSize)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: capability.symbol)
                        .font(.system(size: PermissionMetrics.badgeGlyph, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: PermissionMetrics.badgeSize, height: PermissionMetrics.badgeSize)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: PermissionMetrics.badgeRim))
                        .offset(x: PermissionMetrics.badgeOffset, y: PermissionMetrics.badgeOffset)
                }
                .accessibilityHidden(true)
                .padding(.top, PermissionMetrics.iconTop)

            VStack(spacing: PermissionMetrics.textSpacing) {
                Text(capability.ask(app.name))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(capability.purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if systemWillAsk {
                    Text("If you allow it, iOS asks once for Shelf too.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: PermissionMetrics.buttonSpacing) {
                Button { answer(.allow) } label: {
                    Text("Allow")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: PermissionMetrics.buttonHeight)
                }
                .buttonStyle(.glassProminent)
                Button { answer(.deny) } label: {
                    Text("Don’t Allow")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: PermissionMetrics.buttonHeight)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, PermissionMetrics.padding)
        .padding(.bottom, PermissionMetrics.bottomPadding)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
    }
}

enum PermissionMetrics {
    static let iconSize: CGFloat = 64
    static let iconTop: CGFloat = 28
    static let badgeSize: CGFloat = 26
    static let badgeGlyph: CGFloat = 12
    static let badgeRim: CGFloat = 2
    static let badgeOffset: CGFloat = 6
    static let spacing: CGFloat = 20
    static let textSpacing: CGFloat = 8
    static let buttonSpacing: CGFloat = 10
    static let buttonHeight: CGFloat = 42
    static let padding: CGFloat = 24
    static let bottomPadding: CGFloat = 12
    /// Settings › Permissions' row icons.
    static let rowIconSize: CGFloat = 29
}

/// Shows `PermissionSheet` over whatever is in front: the Home Screen, an
/// app's card, or the New App sheet. The sheet is SwiftUI (plan §0.2); it's
/// presented from UIKit because the gate is asked from anywhere, often
/// while a SwiftUI sheet is already up, which SwiftUI's `.sheet` can't stack
/// on from the root.
///
/// It fits its content, sits in the system's floating sheet glass, and
/// can't be swiped away: like iOS's alert, it waits for an answer.
@MainActor
final class PermissionSheetAsker: PermissionAsker {
    private struct Showing {
        var slug: String
        var controller: UIViewController
        var answer: CheckedContinuation<PermissionChoice, Never>
    }

    private var showing: Showing?

    func ask(_ capability: Capability, for app: AppMeta, systemWillAsk: Bool) async -> PermissionChoice {
        guard let presenter = Self.frontmost() else { return .dismissed }
        return await withCheckedContinuation { continuation in
            let host = UIHostingController(rootView: AnyView(EmptyView()))
            host.rootView = AnyView(PermissionSheet(capability: capability, app: app, systemWillAsk: systemWillAsk) { [weak self, weak host] choice in
                guard let self, let host else { return }
                self.finish(host, with: choice)
            })
            host.view.backgroundColor = .clear
            host.isModalInPresentation = true
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                let width = presenter.view.window?.bounds.width ?? presenter.view.bounds.width
                let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
                sheet.detents = [.custom(identifier: .init("permission")) { context in
                    min(fitted, context.maximumDetentValue)
                }]
                sheet.prefersGrabberVisible = false
            }
            showing = Showing(slug: app.slug, controller: host, answer: continuation)
            presenter.present(host, animated: true)
        }
    }

    func dismiss(for slug: String) {
        guard let showing, showing.slug == slug else { return }
        finish(showing.controller, with: .dismissed)
    }

    /// The answer is given once the sheet has gone, so iOS's prompt, if it
    /// follows, comes up over a clear screen.
    private func finish(_ controller: UIViewController, with choice: PermissionChoice) {
        guard let showing, showing.controller === controller else { return }
        self.showing = nil
        if let presenter = controller.presentingViewController {
            presenter.dismiss(animated: true) { showing.answer.resume(returning: choice) }
        } else {
            showing.answer.resume(returning: choice)
        }
    }

    /// The view controller in front of the key window, not one on its way out.
    private static func frontmost() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
