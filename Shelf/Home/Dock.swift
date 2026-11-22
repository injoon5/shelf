import SwiftUI

/// The dock's glass, by itself, so it can share a `GlassEffectContainer` with
/// the search pill while its icons sit in a layer above.
struct DockGlass: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry

    var body: some View {
        let frame = geometry.dockFrame
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .glassEffect(.regular, in: .rect(cornerRadius: geometry.dockRadius, style: .continuous))
            .onDrop(of: [.plainText], delegate: DockDropDelegate(geometry: geometry, library: library, model: model))
            .position(x: frame.midX, y: frame.midY)
    }
}

/// The dock's icons: the apps the user pinned, then Settings, which never
/// leaves. No labels, as on Springboard.
struct DockIcons: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    var geometry: HomeGeometry
    var labelSize: CGFloat

    var body: some View {
        let pinned = library.layout.dock.compactMap { library.app($0) }
        let count = pinned.count + 1
        ZStack {
            ForEach(Array(pinned.enumerated()), id: \.element.id) { index, app in
                HomeIcon(app: app, geometry: geometry, labelSize: labelSize, showsLabel: false)
                    .position(geometry.dockCenter(index, of: count))
            }
            Button {
                if model.isEditing { model.stopEditing() }
                model.sheet = .settings
            } label: {
                IconArt(face: .settings, size: geometry.iconSize).modifier(IconPress())
            }
            .buttonStyle(IconButtonStyle())
            .modifier(Jiggle(isOn: model.isEditing))
            .position(geometry.dockCenter(count - 1, of: count))
        }
    }
}
