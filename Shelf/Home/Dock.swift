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

/// The dock's icons, Settings among them wherever it was put. No labels,
/// as on Springboard.
struct DockIcons: View {
    @Environment(LibraryStore.self) private var library
    var geometry: HomeGeometry
    var labelSize: CGFloat

    var body: some View {
        let items = library.layout.dock.compactMap { library.item($0) }
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HomeIcon(item: item, geometry: geometry, labelSize: labelSize, showsLabel: false)
                    .position(geometry.dockCenter(index, of: items.count))
            }
        }
    }
}
