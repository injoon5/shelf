import SwiftUI

/// One app on the Home Screen or in the dock: artwork, label, and everything
/// a finger can do to it.
struct HomeIcon: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.zoomNamespace) private var zoom
    var app: CachedApp
    var geometry: HomeGeometry
    var labelSize: CGFloat
    var showsLabel = true

    private var face: IconFace { IconFace(app.meta) }

    var body: some View {
        // A long press means one thing at a time: the menu on a still Home
        // Screen, a drag once the icons are jiggling. (Offered together, the
        // menu's lifted preview swallows the drag and no drop target hears it.)
        // The system lifts and drags a snapshot of the icon itself, cut to its
        // own outline: one corner shape in every state, no label, and the
        // system's own lift (a slight scale, a soft shadow, the rest dimmed).
        Group {
            if model.isEditing {
                button
                    .contentShape(.dragPreview, IconOutline(size: geometry.iconSize))
                    .onDrag {
                        model.lifted(app.slug)
                        return NSItemProvider(object: app.slug as NSString)
                    }
            } else {
                button
                    .contentShape(.contextMenuPreview, IconOutline(size: geometry.iconSize))
                    .contextMenu { menu }
            }
        }
        .modifier(Jiggle(isOn: model.isEditing))
        .modifier(Shake(trigger: model.refusals[app.slug] ?? 0))
        .opacity(model.dragging == app.slug ? 0 : 1)
    }

    private var button: some View {
        Button {
            Task { await model.open(app.slug, in: library) }
        } label: {
            VStack(spacing: HomeMetrics.labelGap) {
                art
                if showsLabel {
                    IconLabel(name: app.meta.name, isNew: app.isNew, size: labelSize, width: geometry.labelWidth)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(app.meta.name)
    }

    private var art: some View {
        PendingIcon(face: face, size: geometry.iconSize, isRunnable: app.isRunnable,
                    isDownloading: library.downloading.contains(app.slug))
            .modifier(IconPress(size: geometry.iconSize))
            .modifier(ZoomSource(id: app.slug, size: geometry.iconSize, namespace: zoom))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Change…", systemImage: "wand.and.sparkles") {
            model.sheet = .change(app)
        }
        Button("Reload App", systemImage: "arrow.clockwise") {
            Task { _ = await library.fetch(app.slug) }
        }
        Button("Copy Source", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = library.source(for: app.slug)
        }
        .disabled(!app.isRunnable)
        if app.meta.revertible {
            Button("Revert", systemImage: "arrow.uturn.backward") {
                Task { await library.revert(app.slug) }
            }
        }
        Divider()
        Button("Edit Home Screen", systemImage: "apps.iphone") {
            model.startEditing()
        }
    }
}

/// The icon an app grows out of and shrinks back into.
struct ZoomSource: ViewModifier {
    var id: String
    var size: CGFloat
    /// Nil takes this icon out of the running: another copy of it (a search
    /// result, say) is the one on screen.
    var namespace: Namespace.ID?
    @Namespace private var nowhere

    func body(content: Content) -> some View {
        content.matchedTransitionSource(id: id, in: namespace ?? nowhere) { source in
            source.clipShape(HomeMetrics.iconShape(size))
        }
    }
}

/// An icon whose source may still be on the way. While it is, the tile
/// darkens and the install pie takes the glyph's place, so the two never
/// draw over each other.
///
/// A brand-new app has nothing else to show, so its pie appears at once. An
/// update to an app that already runs shows nothing unless it is slow.
private struct PendingIcon: View {
    var face: IconFace
    var size: CGFloat
    var isRunnable: Bool
    var isDownloading: Bool
    @State private var progress = 0.0
    @State private var isSlow = false

    private var isPending: Bool { !isRunnable || (isDownloading && isSlow) }

    var body: some View {
        IconArt(face: face, size: size, showsGlyph: !isPending)
            .overlay {
                if isPending {
                    ZStack {
                        HomeMetrics.iconShape(size).fill(.black.opacity(HomeMetrics.pendingDim))
                        InstallPie(progress: progress, size: size * HomeMetrics.pieRatio)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .animation(Motion.fade, value: isPending)
            .task(id: isDownloading) {
                guard isDownloading else {
                    isSlow = false
                    withAnimation(Motion.pie) { progress = isRunnable ? 1 : 0 }
                    return
                }
                // The real size is a few kilobytes, gone in one packet, so the pie
                // creeps toward full and finishes when the download does.
                progress = 0
                withAnimation(Motion.pieCreep) { progress = Motion.pieCreepTarget }
                try? await Task.sleep(for: Motion.spinnerDelay)
                if !Task.isCancelled { isSlow = true }
            }
    }
}
