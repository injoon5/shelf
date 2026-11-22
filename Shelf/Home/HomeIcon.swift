import SwiftUI

/// One app on the Home Screen or in the dock: artwork, label, and everything
/// a finger can do to it.
struct HomeIcon: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(\.zoomNamespace) private var zoom
    var app: CachedApp
    var geometry: HomeGeometry
    var labelSize: CGFloat
    var showsLabel = true

    private var face: IconFace { IconFace(app.meta) }

    var body: some View {
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
        .contextMenu {
            menu
        } preview: {
            IconArt(face: face, size: geometry.iconSize * 2)
        }
        .onDrag {
            model.beginDrag(app.slug)
            return NSItemProvider(object: app.slug as NSString)
        } preview: {
            IconArt(face: face, size: geometry.iconSize)
        }
        .modifier(Jiggle(isOn: model.isEditing))
        .modifier(Shake(trigger: model.refusals[app.slug] ?? 0))
        .opacity(model.dragging == app.slug ? 0 : 1)
    }

    private var art: some View {
        IconArt(face: face, size: geometry.iconSize)
            .modifier(IconPress())
            .overlay {
                PendingOverlay(isRunnable: app.isRunnable, isDownloading: library.downloading.contains(app.slug),
                               size: geometry.iconSize)
            }
            .modifier(ZoomSource(id: app.slug, radius: geometry.iconRadius, namespace: zoom))
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
    var radius: CGFloat
    /// Nil takes this icon out of the running: another copy of it (a search
    /// result, say) is the one on screen.
    var namespace: Namespace.ID?
    @Namespace private var nowhere

    func body(content: Content) -> some View {
        content.matchedTransitionSource(id: id, in: namespace ?? nowhere) { source in
            source.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// Dims an icon and draws the install pie while its source is on the way.
///
/// A brand-new app has nothing else to show, so its pie appears at once. An
/// update to an app that already runs shows nothing unless it is slow.
private struct PendingOverlay: View {
    var isRunnable: Bool
    var isDownloading: Bool
    var size: CGFloat
    @State private var progress = 0.0
    @State private var isSlow = false

    private var isVisible: Bool { !isRunnable || (isDownloading && isSlow) }

    var body: some View {
        ZStack {
            if isVisible {
                RoundedRectangle(cornerRadius: size * HomeMetrics.iconCornerRatio, style: .continuous)
                    .fill(.black.opacity(HomeMetrics.pendingDim))
                InstallPie(progress: progress, size: size * HomeMetrics.pieRatio)
            }
        }
        .animation(Motion.fade, value: isVisible)
        .allowsHitTesting(false)
        .task(id: isDownloading) {
            guard isDownloading else {
                isSlow = false
                withAnimation(Motion.pie) { progress = isRunnable ? 1 : 0 }
                return
            }
            // The real size is a few kilobytes, gone in one packet, so the pie
            // creeps toward full and finishes when the download does.
            progress = 0
            withAnimation(.easeOut(duration: Motion.pieCreepTime)) { progress = Motion.pieCreep }
            try? await Task.sleep(for: Motion.spinnerDelay)
            if !Task.isCancelled { isSlow = true }
        }
    }
}
