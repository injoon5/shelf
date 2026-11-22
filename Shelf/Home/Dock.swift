import SwiftUI

/// The dock's glass and its drop target, apart from its icons, which sit
/// above it.
struct DockGlass: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var geometry: HomeGeometry

    var body: some View {
        let frame = geometry.dockFrame
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .glassEffect(HomeMetrics.glass(scheme), in: .rect(cornerRadius: geometry.dockRadius, style: .continuous))
            .onDrop(of: [.text], delegate: DockDropDelegate(geometry: geometry, library: library, model: model))
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
        ZStack {
            ForEach(Array(pinned.enumerated()), id: \.element.id) { index, app in
                HomeIcon(app: app, geometry: geometry, labelSize: labelSize, showsLabel: false)
                    .position(geometry.pinnedCenter(index, pinned: pinned.count))
            }
            Button {
                if model.isEditing { model.stopEditing() }
                model.sheet = .settings
            } label: {
                IconArt(face: .settings, size: geometry.iconSize).modifier(IconPress(size: geometry.iconSize))
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Settings")
            .modifier(Jiggle(isOn: model.isEditing))
            .position(geometry.settingsCenter(pinned: pinned.count))
        }
    }
}
