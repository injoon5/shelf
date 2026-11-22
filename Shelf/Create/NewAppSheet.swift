import SwiftUI

/// New App, and Change… for an existing one. You describe it, copy the prompt
/// into any chat model or agent, and the app comes back one of two ways: the
/// agent installs it with the key in the prompt, or you paste the reply here,
/// try it, and install it yourself.
struct NewAppSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var model: CreateModel

    /// `source` is the app's current source, for the change prompt.
    init(app: CachedApp?, source: String?) {
        _model = State(initialValue: CreateModel(app: app, source: source))
    }

    var body: some View {
        Group {
            if model.reply == nil {
                ComposeView(model: model)
                    .transition(.opacity)
            } else {
                PreviewView(model: model)
                    .transition(.opacity)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.success, trigger: model.installs)
        .sensoryFeedback(.error, trigger: model.rejections)
        .task { await model.mint() }
        // Restarting on every return to the foreground gives the check that
        // matters most: you were just in the agent's app.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.watch(library: library)
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
    }
}

// MARK: - Compose

private struct ComposeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShelfSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var model: CreateModel
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: CreateMetrics.spacing) {
            SheetHeader(title: model.app.map { $0.meta.name } ?? "New App") { dismiss() }

            TextField(model.isChange ? "Describe the change" : "Describe the app", text: $model.idea, axis: .vertical)
                .font(.title3)
                .focused($isFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(.rect)
                .onTapGesture { isFocused = true }

            if model.isChange {
                Toggle("Include Source", isOn: $settings.includeSource)
            }

            HStack(spacing: CreateMetrics.spacing) {
                Button {
                    model.copy(includeSource: settings.includeSource)
                } label: {
                    Label(model.didCopy ? "Copied" : "Copy Prompt", systemImage: model.didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: CreateMetrics.buttonHeight)
                }
                .buttonStyle(.glassProminent)

                ShareLink(item: model.prompt(includeSource: settings.includeSource)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: CreateMetrics.buttonHeight, minHeight: CreateMetrics.buttonHeight)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Share Prompt")
            }
            .disabled(!model.hasIdea)

            // The system's own paste button: iOS asks nothing before it reads.
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in model.paste(text, library: library) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
        }
        .padding(CreateMetrics.padding)
        .onAppear { isFocused = true }
    }
}

// MARK: - Preview

private struct PreviewView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    var model: CreateModel
    @State private var connectivity = Connectivity.shared
    @State private var didCopyError = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: CreateMetrics.spacing) {
            SheetHeader(title: model.isChange ? "Update" : "New App", back: { model.discardReply() }) { dismiss() }

            if let meta = model.previewMeta, let reply = model.reply {
                stage(meta, source: reply.source)

                HStack(spacing: CreateMetrics.spacing) {
                    IconArt(face: IconFace(meta), size: CreateMetrics.tileSize)
                    VStack(alignment: .leading, spacing: CreateMetrics.fieldSpacing) {
                        TextField("Name", text: $model.name)
                            .font(.headline)
                            .onChange(of: model.name) { _, name in
                                if name.count > CreateModel.nameLimit { model.name = CreateModel.fitting(name) }
                            }
                        if model.isChange {
                            Text(model.slug)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("slug", text: $model.slug)
                                .font(.footnote.monospaced())
                                .foregroundStyle(model.isSlugValid && !model.isSlugTaken(in: library) ? .secondary : Color.red)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    installButton
                }

                if let failure = model.failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
        }
        .padding(CreateMetrics.padding)
        .animation(Motion.quick, value: model.failure)
    }

    private func stage(_ meta: AppMeta, source: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: CreateMetrics.previewRadius, style: .continuous)
        return AppStage(app: meta, source: source,
                        // A change is tried against a copy of the app's real data; nothing here is saved.
                        store: .scratch(copying: model.app?.slug)) { error in
            model.previewFailed(error)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: CreateMetrics.previewBorder) }
        .overlay(alignment: .bottom) {
            if let error = model.compileError {
                // A broken reply goes back to the model with the lines around the failure.
                Button {
                    UIPasteboard.general.string = error.report
                    didCopyError = true
                } label: {
                    Label(didCopyError ? "Copied" : "Copy Error", systemImage: didCopyError ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .padding(CreateMetrics.padding)
                .task(id: didCopyError) {
                    guard didCopyError else { return }
                    try? await Task.sleep(for: Motion.copiedStay)
                    didCopyError = false
                }
            }
        }
        // The preview is keyed to the source alone: renaming the app mustn't restart it.
        .id(source)
    }

    private var installButton: some View {
        Button {
            Task { await model.installReply(library: library) }
        } label: {
            ZStack {
                Text(connectivity.isOnline ? (model.isChange ? "Update" : "Install") : "Offline")
                    .opacity(model.isInstalling ? 0 : 1)
                if model.isInstalling { ProgressView() }
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: CreateMetrics.buttonHeight)
        }
        .buttonStyle(.glassProminent)
        .disabled(!connectivity.isOnline || !model.canInstall(in: library))
    }
}

// MARK: - Header

private struct SheetHeader: View {
    var title: String
    var back: (() -> Void)?
    var close: () -> Void

    var body: some View {
        HStack(spacing: CreateMetrics.spacing) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: CreateMetrics.closeSize, height: CreateMetrics.closeSize)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Back")
            }
            Text(title)
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: CreateMetrics.closeSize, height: CreateMetrics.closeSize)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")
        }
    }
}
