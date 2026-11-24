import Foundation
import Kiln
import os
import QuartzCore
import SwiftUI

/// What Shelf gives every run of an app (plan §1.7): its data, its settings,
/// its folder, and source parsed ahead of time.
@MainActor
struct AppHost {
    var data: AppData
    var defaults: AppDefaults
    var files: AppFiles
    var builds: Prebuilds

    /// A library's own, so a demo library's runs never touch the real data.
    init(data: AppData, defaults: AppDefaults = .standard, files: AppFiles = .standard, builds: Prebuilds = .shared) {
        self.data = data
        self.defaults = defaults
        self.files = files
        self.builds = builds
    }
}

/// One open of one app: its Kiln context and what Kiln built. Closing the
/// app's card tears it down: Kiln cancels the app's tasks and timers and
/// stops whatever its bridges started, and a permission sheet still up
/// for it goes.
@MainActor
final class AppRun {
    let context: KilnContext
    let permissions: any AppPermissions
    var result: KilnResult?

    init(context: KilnContext, permissions: any AppPermissions) {
        self.context = context
        self.permissions = permissions
    }

    var isTornDown: Bool { context.isTornDown }

    func tearDown() {
        result?.tearDown()
        context.tearDown()
        permissions.cancelRequests()
    }
}

/// Builds the Kiln context for a run of an app.
@MainActor
enum RunContext {
    static let log = Logger(subsystem: "dev.ij5.shelf", category: "run")

    /// An installed app, for real: its own settings and folder, its data
    /// session, and the permission gate bound to it.
    static func installed(_ app: AppMeta, session: DBSession, permissions: any AppPermissions, host: AppHost) -> KilnContext {
        DBBridge.register()
        let files = host.files.kiln(for: app.slug) ?? KilnFiles(root: FileManager.default.temporaryDirectory.appending(path: "shelf-unsafe-slug"))
        let context = KilnContext(slug: app.slug, name: app.name, defaults: host.defaults.suite(for: app.slug), files: files,
                                  capabilities: PermissionsGate(permissions))
        context.provide(session)
        context.provide(AppAudio.session())
        return context
    }

    /// A try-out (the New App preview): the real capabilities, after the same
    /// sheet, but settings and a folder that start empty and go when it ends,
    /// and a scratch data session.
    static func scratch(_ app: AppMeta, session: DBSession, permissions: any AppPermissions) -> KilnContext {
        DBBridge.register()
        let id = UUID().uuidString
        let suite = "shelf.preview.\(id)"
        let folder = FileManager.default.temporaryDirectory.appending(path: "shelf-preview-\(id)", directoryHint: .isDirectory)
        let context = KilnContext(slug: app.slug, name: app.name, defaults: UserDefaults(suiteName: suite) ?? UserDefaults(),
                                  files: KilnFiles(root: folder), capabilities: PermissionsGate(permissions))
        context.provide(session)
        context.provide(AppAudio.session())
        // Its web pages' cookies and storage go with it.
        context.provide(KilnEphemeralWebsiteData())
        context.onTearDown {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        return context
    }

    /// A check (`Kiln.validate`): Kiln's stub context, with a session for
    /// `DB` and stub permissions that answer at once.
    static func check(_ app: AppMeta, session: DBSession, permissions: StubAppPermissions = StubAppPermissions()) -> KilnContext {
        DBBridge.register()
        let context = KilnContext.stub(slug: app.slug, name: app.name, capabilities: PermissionsGate(permissions))
        context.provide(session)
        return context
    }
}

/// Shelf's per-app permissions as Kiln's capability gate.
@MainActor
final class PermissionsGate: KilnCapabilityGate {
    let permissions: any AppPermissions

    init(_ permissions: any AppPermissions) {
        self.permissions = permissions
    }

    func request(_ capability: KilnCapability) async -> Bool {
        guard let capability = Capability(capability) else { return false }
        return await permissions.request(capability)
    }

    func status(_ capability: KilnCapability) -> KilnPermissionStatus {
        guard let capability = Capability(capability) else { return .denied }
        return switch permissions.status(capability) {
        case .notAsked: .notAsked
        case .allowed: .allowed
        case .denied: .denied
        }
    }

    func cancelRequests() {
        permissions.cancelRequests()
    }

    func answerWithoutAsking(_ capability: KilnCapability) -> Bool {
        guard let capability = Capability(capability) else { return false }
        if let stub = permissions as? StubAppPermissions { return stub.answer(capability) }
        return permissions.status(capability) == .allowed
    }
}

extension Capability {
    /// Kiln's name for it: the same raw value.
    init?(_ capability: KilnCapability) {
        self.init(rawValue: capability.rawValue)
    }
}

/// Source parsed off the main thread before the app's card asks for it
/// (plan §0.8 item 5): a finger landing on an icon starts the parse, so
/// by the time the card has grown, Kiln only has to build.
@MainActor
final class Prebuilds {
    static let shared = Prebuilds()

    private struct Entry {
        var source: String
        var parse: Task<KilnParsedSource, Never>
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    /// How many parses are kept for apps pressed but not (yet) opened.
    private let limit = 4

    /// Starts parsing `source` for `slug`, unless that parse is under way.
    func prepare(_ slug: String, source: String) {
        if entries[slug]?.source == source { return }
        entries[slug] = Entry(source: source, parse: Task.detached(priority: .userInitiated) { Kiln.parse(source) })
        order.removeAll { $0 == slug }
        order.append(slug)
        while order.count > limit { entries[order.removeFirst()] = nil }
    }

    /// The parse for this run: the one prepared, or a new one, off the main
    /// thread either way. Each parse is for one run, so it's handed out once.
    func take(_ slug: String, source: String) async -> KilnParsedSource {
        prepare(slug, source: source)
        let entry = entries.removeValue(forKey: slug)!
        order.removeAll { $0 == slug }
        return await entry.parse.value
    }

    /// Whether a parse for exactly this source is waiting.
    func isPrepared(_ slug: String, source: String) -> Bool {
        entries[slug]?.source == source
    }

    /// Kiln's registry and engine, warmed while nothing is moving: the first
    /// app opened after launch then builds as fast as the rest.
    static func warmUp() {
        let start = CACurrentMediaTime()
        let context = KilnContext.stub(slug: "warm-up", name: "Warm-up")
        let result = Kiln.run(warmUpSource, context: context)
        defer { result.tearDown() }
        guard let view = result.view else { return }
        // Drawn offscreen once: SwiftUI's and the renderer's first-time costs
        // go here instead of into the first app's first frame.
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 600))
        renderer.scale = 1
        _ = renderer.uiImage
        LaunchTiming.log.debug("warm-up \(Int((CACurrentMediaTime() - start) * 1000), privacy: .public) ms")
    }

    /// The views apps use most, once each.
    private static let warmUpSource = """
    import SwiftUI
    struct Item: Identifiable { let id = UUID(); var name: String; var done = false }
    struct ContentView: View {
        @State private var items = [Item(name: "One"), Item(name: "Two", done: true)]
        @State private var text = ""
        @State private var on = true
        @State private var value = 0.5
        var body: some View {
            NavigationStack {
                List {
                    Section("Items") {
                        ForEach(items) { item in
                            HStack {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.tint)
                                Text(item.name).font(.headline)
                                Spacer()
                                Text(Date(), style: .time).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        TextField("Name", text: $text)
                        Toggle("On", isOn: $on)
                        Slider(value: $value)
                        Button("Add") { items.append(Item(name: text)) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .navigationTitle("Warm-up")
                .toolbar { Button("Edit", systemImage: "pencil") {} }
            }
            .overlay {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12).fill(.blue.gradient).frame(height: 40)
                    ProgressView(value: value)
                    Label("Label", systemImage: "star").padding().background(.thinMaterial, in: Capsule())
                }
                .padding()
                .opacity(0.01)
            }
        }
    }
    """
}
