import SwiftUI

/// One icon on the Home Screen, in the dock or among search results: an app
/// or Settings, with its artwork, label, and everything a finger can do to it.
struct HomeIcon: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeModel.self) private var model
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.iconPlace) private var place
    var item: HomeItem
    var geometry: HomeGeometry
    var labelSize: CGFloat
    var showsLabel = true

    private var face: IconFace {
        switch item {
        case .app(let app): IconFace(app.meta)
        case .settings: .settings
        }
    }

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
                        model.lifted(item.id)
                        return NSItemProvider(object: item.id as NSString)
                    }
            } else {
                button
                    .contentShape(.contextMenuPreview, IconOutline(size: geometry.iconSize))
                    .contextMenu { menu }
            }
        }
        .modifier(Jiggle(isOn: model.isEditing))
        .modifier(Shake(trigger: model.refusals[item.id] ?? 0))
        .opacity(model.dragging == item.id ? 0 : 1)
        // The label's size comes from the stage under this same cap; the
        // rest of the icon stops growing where the label does.
        .dynamicTypeSize(...HomeMetrics.textSizeCap)
    }

    private var button: some View {
        Button {
            Task { await model.open(item.id, in: library) }
        } label: {
            VStack(spacing: HomeMetrics.labelGap) {
                art
                if showsLabel {
                    IconLabel(name: item.name, isNew: item.app?.isNew == true, size: labelSize, width: geometry.labelWidth)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(item.name)
    }

    private var art: some View {
        PendingIcon(face: face, size: geometry.iconSize, isRunnable: item.app?.isRunnable ?? true,
                    isDownloading: library.downloading.contains(item.id))
            .modifier(IconPress(size: geometry.iconSize))
            .modifier(CardSource(key: IconKey(slug: item.id, place: place)))
    }

    /// Settings' menu has only Edit Home Screen: it can't be changed,
    /// reloaded, copied, reverted or deleted.
    @ViewBuilder
    private var menu: some View {
        if let app = item.app {
            appActions(app)
            Divider()
        }
        Button("Edit Home Screen", systemImage: "apps.iphone") {
            model.startEditing()
        }
    }

    @ViewBuilder
    private func appActions(_ app: CachedApp) -> some View {
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
    }
}

/// The icon an app's card grows out of and shrinks back into. It tells the
/// stage where it is, and while the card stands in for it, it isn't drawn.
struct CardSource: ViewModifier {
    @Environment(StageLayout.self) private var stage
    var key: IconKey

    func body(content: Content) -> some View {
        content
            .opacity(stage.cardIcons.contains(key.slug) ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(StageLayout.space))
            } action: { frame in
                stage.iconFrames[key] = frame
            }
            .onDisappear { stage.iconFrames[key] = nil }
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
