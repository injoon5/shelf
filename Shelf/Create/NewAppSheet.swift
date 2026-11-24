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

    /// A sheet over a model already made (tests show one with a reply in it).
    init(model: CreateModel) {
        _model = State(initialValue: model)
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
        .dynamicTypeSize(...ShelfMetrics.textSizeCap)
        .sensoryFeedback(.success, trigger: model.installs)
        .sensoryFeedback(.error, trigger: model.rejections)
        .task { await model.mint(library: library) }
        #if DEBUG
        .task { if let reply = Demo.reply, model.reply == nil, !model.isChange { model.paste(reply, library: library) } }
        #endif
        // Restarting on every return to the foreground gives the check that
        // matters most: you were just in the agent's app.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.watch(library: library)
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { model.closed(library.permissions) }
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
                .disabled(!model.hasIdea)

                Menu {
                    ShareLink(item: model.prompt(includeSource: settings.includeSource)) {
                        Label("Share Prompt", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!model.hasIdea)
                    Button("Copy Token", systemImage: "key") { model.copyToken() }
                        .disabled(!model.hasToken)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: CreateMetrics.buttonHeight, minHeight: CreateMetrics.buttonHeight)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("More")
            }
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

    var body: some View {
        VStack(spacing: CreateMetrics.spacing) {
            SheetHeader(title: model.isChange ? "Update" : "New App", back: { model.discardReply() }) { dismiss() }
                .padding([.horizontal, .top], CreateMetrics.padding)

            if let meta = model.previewMeta, let reply = model.reply {
                if let error = model.checkError ?? model.compileError {
                    // Nothing to try and nothing to install: the error is the
                    // sheet, with no preview frame, and no name or Install
                    // under it. Copy for Agents sends it back with the
                    // sheet's key, to be fixed and installed.
                    ErrorScreen(face: IconFace(meta), name: meta.name, error: error,
                                title: "\(meta.name) can’t be installed") { model.fixPrompt(for: error) }
                        .transition(.opacity)
                } else {
                    tryOut(meta, source: reply.source)
                        .padding([.horizontal, .bottom], CreateMetrics.padding)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.quick, value: model.checkError ?? model.compileError)
    }

    /// The reply running, and what it will be installed as.
    private func tryOut(_ meta: AppMeta, source: String) -> some View {
        @Bindable var model = model
        return VStack(spacing: CreateMetrics.spacing) {
            stage(meta, source: source)

            HStack(spacing: CreateMetrics.spacing) {
                IconImage(face: IconFace(meta), size: CreateMetrics.tileSize)
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

            if !model.warnings.isEmpty {
                warnings
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: model.failure)
        .animation(Motion.quick, value: model.warnings)
    }

    /// What Kiln accepts but doesn't do yet: listed, never blocking.
    private var warnings: some View {
        let shown = model.warnings.prefix(CreateMetrics.warningsShown)
        let more = model.warnings.count - shown.count
        return VStack(alignment: .leading, spacing: CreateMetrics.fieldSpacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text((try? AttributedString(markdown: warning)) ?? AttributedString(warning))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if more > 0 {
                Text(more == 1 ? "1 more warning" : "\(more) more warnings")
                    .padding(.leading, CreateMetrics.warningIndent)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(CreateMetrics.warningLines)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func stage(_ meta: AppMeta, source: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: CreateMetrics.previewRadius, style: .continuous)
        return AppStage(app: meta, source: source,
                        // A change is tried against a copy of the app's real data; nothing here is saved.
                        store: .scratch(copying: model.app?.slug), host: library.host,
                        // The real capabilities, after the same sheet an installed app gets.
                        permissions: model.previewPermissions(library.permissions),
                        // Failing while it runs blocks Install too, and the sheet shows the error instead.
                        onError: { error in model.previewFailed(error) },
                        errorTitle: "\(meta.name) can’t be installed",
                        fixPrompt: { model.fixPrompt(for: $0) })
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: CreateMetrics.previewBorder) }
            // The preview is keyed to the source alone: renaming the app mustn't restart it.
            .id(source)
    }

    private var installButton: some View {
        Button {
            Task { await model.installReply(library: library) }
        } label: {
            ZStack {
                Text(connectivity.isOnline ? (model.isChange ? "Update" : "Install") : "Offline")
                    .opacity(model.isInstalling || model.isChecking ? 0 : 1)
                // Installing, or `Kiln.validate` still trying the reply.
                if model.isInstalling || model.isChecking { ProgressView() }
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
