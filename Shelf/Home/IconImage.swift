import SwiftUI
import UIKit

/// The Home Screen's icon (`IconArtView`) in SwiftUI, for the sheets that
/// show one (the New App preview, the error screen): one
/// renderer everywhere. It reads the icon tone from the window, as every
/// icon does, unless the SwiftUI around it sets `\.iconTone`.
struct IconImage: UIViewRepresentable {
    var face: IconFace
    var size: CGFloat
    var isPressed = false

    func makeUIView(context: Context) -> Holder {
        Holder(art: IconArtView(face: face, iconSize: size))
    }

    func updateUIView(_ holder: Holder, context: Context) {
        holder.art.face = face
        holder.art.setPressed(isPressed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Holder, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    /// Keeps the art, whose bounds are centred on its origin, in the middle.
    final class Holder: UIView {
        let art: IconArtView

        init(art: IconArtView) {
            self.art = art
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            addSubview(art)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            art.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }
}
