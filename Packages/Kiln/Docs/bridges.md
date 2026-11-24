# Adding a bridge

Everything native an app can name in Kiln is a **bridge** in the registry (PLAN.md §1.4): views, modifiers, types (with their initializers, static members, properties and methods), global functions, protocols, environment values and property wrappers. The engine knows no names of its own. It asks the registry, and anything the registry doesn't have is an error with the author's line.

This page is the guide for adding one. It has one worked example per kind:

- [a view](#a-view);
- [a modifier](#a-modifier);
- [a type with an `async` method](#a-type-with-an-async-method);
- [a host bridge](#a-host-bridge);
- [the run's context](#the-runs-context): files, settings, the capability gate, teardown and fakes, which every Round 3 bridge goes through;
- [a protocol proxy](#a-protocol-proxy): native code calling the app's code, for a SwiftUI protocol, a representable, a delegate, `Transferable` and an `async` requirement.

## Where bridges live

`Sources/Kiln/Bridges/<Family>/`, one folder per family, named after `KilnFamily.folder`: `Controls`, `Layout`, `Lists`, `Navigation`, `Gestures`, `Drawing`, `Charts`, `Haptics`, `Sharing`, `Text`, `Units`, `Audio`, `Web`, `Files`, `Photos`, `Camera`, `Motion`, `Location`, `Vision`, `Intelligence`, `Widgets`.

There are also SwiftUI's other families from `Tools/coverage/families.json`:

- `Core`
- `Focus` (Focus & Keyboard)
- `Environment`
- `Accessibility`
- `Scenes`
- `Chart3D`

And families for what isn't SwiftUI:

- `Language` (the standard library)
- `Foundation`
- `Concurrency`
- `Networking`
- `Host` (registered by the app hosting Kiln; there's no folder)

A family with no bridges has no folder. To start one:

1. Make the folder.
2. Add one class named after it, with `@objc(KilnBridges_<Folder>)`. That's how the registry finds it, so no shared file lists families:

   ```swift
   @objc(KilnBridges_Web)
   final class WebBridges: KBridgeFamily {
       override class func register(into r: KRegistry) {
           views(r)        // in this folder's other files, as `extension WebBridges`
           pages(r)
       }
   }
   ```

3. Put the bridges in that folder's files, as `extension WebBridges { static func views(_ r: KRegistry) { … } }`.

Two families never edit the same file. A symbol registered twice, by two families, stops Kiln at launch with both files named.

`RegistryTests.testEveryBridgeFolderIsAFamilyThatRegisters` checks the folder and class names.

## Signatures

An overload is a **signature string**: `label:kind` pairs, in Swift's order.

| Write | Means |
|---|---|
| `_:title` | an unlabeled parameter |
| `spacing:number?` | has a default (can be left out) |
| `_:any...` | variadic |
| `content:content` | a trailing closure keeps its label, as in SwiftUI's declaration |
| `""` | no arguments |

The overload that takes a call is picked like this:

- **By labels.** Overloads are tried in the order declared, and the first that takes the arguments wins. So declare the specific forms before the general ones.
- **By how each argument is written.** A string literal can't bind a closure parameter, and a closure literal can't bind a `title`.
- **Trailing closures, as in Swift.** An unlabeled trailing closure binds the next closure parameter. One with a default is passed over when a later closure parameter needs an argument (SE-0286's forward scan), so `.sheet(isPresented:) { }` binds `content`, not `onDismiss`.
- **By availability on the running OS.** An overload the OS doesn't have is skipped. If it was the only match, the error says which iOS it needs (`introduced: "26.0"` on the form).

When no overload takes a call, the author sees what there is:

```
Line 12: Kiln has no Toggle(_:isOn:tint:); it has Toggle(_:isOn:), Toggle(_:systemImage:isOn:) and Toggle(isOn:label:)
```

A signature of `nil` (types and functions only) takes any labels: the bridge reads them itself with `c.arg("label")` and `c.at(n)`. The standard library's methods are like this, because Kiln has always taken them loosely. Prefer real signatures for anything new: they're what the manifest, the checker (§1.8) and the coverage report read.

## Argument kinds

The kind says what the engine evaluates an argument against, which syntax it accepts, and what's checked before the bridge runs.

| Kind | Evaluated | Checked |
|---|---|---|
| `any` | with no expected type | — |
| `TypeName` (capitalized) | against that type, so implicit members resolve: `Color` makes `.red` a color, `HorizontalAlignment` keeps `.leading` symbolic for the view | — |
| `[TypeName]` | each element against the type | — |
| `title` | a string literal is a `LocalizedStringKey` (`"\(n) pages"` reads "1,400 pages") | — |
| `string`, `number`, `bool` | as written (a `1` stays an `Int` until the bridge reads it) | when read |
| `binding` | `$value`; `.constant(v)` too | yes: anything else is an error naming the parameter |
| `content` | a `@ViewBuilder` closure, built when shown | — |
| `closure`, `action` | a closure; `action` means one an event fires, which `validate` fires too | — |
| `view` | a view value | — |

## What a bridge gets: `KCall`

Arguments are named by label (`"selection"`), by position among the unlabeled ones (`0`), or `.receiver` for the value a method is called on.

| Helper | Returns |
|---|---|
| `c.binding("isOn", Bool.self)` | `Binding<Bool>`, writing back the stored kind (an `Int` stays one) |
| `c.optional("in", ClosedRange<Double>.self)` | the value as a Swift type, or nil |
| `c.required(0, Date.self)` | the value, or an error that names it |
| `c.content()`, `c.content("label")` | the views a closure makes, shown |
| `c.views(…)` | those views as descriptions |
| `c.action("perform")` | a `() -> Void` that runs the closure on an event, with its own step budget |
| `c.title(0)`, `c.string("prompt")`, `c.double`, `c.cg`, `c.int`, `c.bool(_, default:)` | plain values |
| `c.color(0)`, `c.shapeStyle(0)`, `c.font(0)`, `c.angle(0)`, `c.alignment("alignment")`, `c.edges(0)`, `c.unitPoint`, `c.animation` | SwiftUI values |
| `c.symbol("edge")` | the name of a symbolic value: `.leading` is `"leading"` |
| `c.object(DateFormatter.self)` | the native object a method is called on |
| `c.fail("needs …")` | an error reading `Line N: Toggle(_:isOn:): needs …` |
| `c.noMember()` | `Value of type 'X' has no member 'y'` |
| `c.r` | the renderer, for anything else |

`KBridgeable` decodes a value as a Swift type and encodes it back: `Bool`, `Int`, `Double`, `CGFloat`, `String`, `Date`, `Color`, `URL`, `Angle`, `ClosedRange` of those, and `KV` itself. Add a conformance when a bridge needs a new type in a binding.

## A view

`Bridges/Controls/Controls.swift`, `Toggle`:

```swift
r.view("Toggle", .controls) { v in
    v.form("_:title isOn:binding") { c in Toggle(c.title(0), isOn: c.binding("isOn", Bool.self)) }
    v.form("_:title systemImage:string isOn:binding") { c in
        Toggle(isOn: c.binding("isOn", Bool.self)) { Label(c.title(0), systemImage: c.title("systemImage")) }
    }
    v.form("isOn:binding label:content") { c in Toggle(isOn: c.binding("isOn", Bool.self)) { c.content("label") } }
}
```

- The closure is a `@ViewBuilder` and returns the real view. It runs inside the SwiftUI `body` that shows it.
- When the app's code runs, `Toggle(…)` evaluates to a description (`.primitive("Toggle", args, labels)`) that keeps the overload it picked. The transcript, `validate` and the renderer all read that description.
- `v.make { c in … }` changes what the call evaluates to. `Image(uiImage:)` passes an image through this way, and `Text` marks a literal.
- `v.manifestKind = "content"` is for chart marks, toolbar items and tabs.
- `v.engineOnly()` is for views only the engine makes (`UserShape`).

## A modifier

`Bridges/Layout/Layout.swift`, `.padding`:

```swift
r.modifier("padding", .layout, notes: "A length, edges, edges and a length, or `EdgeInsets`.") { m in
    m.form("") { _, view in view.padding() }
    m.form("_:any") { c, view in … }                  // a length, edges or EdgeInsets
    m.form("_:Edge.Set _:number?") { c, view in
        if let n = c.cg(1) { view.padding(c.edges(0), n) } else { view.padding(c.edges(0)) }
    }
}
```

- `form` gets the view, already shown, and returns it modified.
- `formOnBase` gets only `c`, when the modifier needs the **description** of what it's on (`c.base`):
  - `fill` and `stroke` reach the real `Shape`;
  - `onDelete` finds its `ForEach`;
  - `resizable` rebuilds the `Image`.

  `c.view` shows the base when it's needed.
- `m.text { c, t in t.bold() }` makes the modifier keep a `Text` a `Text`, so `Text + Text` and labels keep it.
- `m.styles("ButtonStyle", […])` lists a style modifier's members for the manifest (`style:ButtonStyle.bordered`).
- `m.stub([…])` accepts a modifier with no effect. Mark the bridge `support: .stub` so the manifest and the coverage report count it as missing. A stub is a decision, not a default: an unknown modifier is an error, so only stub what apps write and lose nothing by skipping.
- A form on content that isn't a view takes `receiver: "ChartContent"` (or `ToolbarContent`, `TabContent`…). The manifest lists it as `modifier:ChartContent.<name>`.

## A type with an async method

Types hold values: `.native(.object(kind, KRef(object)))` for a native object, or a `KNative` case for a value type. Here is the shape a Round 2 `WebPage` bridge would take:

```swift
r.type("WebPage", .web, notes: "Load a URL or HTML; read title, url and isLoading.") { t in
    t.initializer("") { _ in .native(.object("WebPage", KRef(WebPage()))) }
    t.property("title") { c in .string(c.object(WebPage.self)?.title ?? "") }
    t.method("load", "_:URL") { c in
        guard let page = c.object(WebPage.self), let url = c.url(0) else { throw c.fail("needs a URL") }
        page.load(URLRequest(url: url))
        return .void
    }
    // `try await page.callJavaScript("…")`: an async method returns what `await` waits on,
    // and says so with `async: true`, so `Kiln.check` reports a call with no `await`.
    t.method("callJavaScript", "_:string", async: true) { c in
        guard let page = c.object(WebPage.self), let js = c.string(0) else { throw c.fail("needs JavaScript") }
        return .suspension(KSuspension.async(headless: { .nilValue }) {
            let result = try await page.callJavaScript(js)
            return result.map { .string(String(describing: $0)) } ?? .nilValue
        })
    }
}
```

**Static members:**

- `t.staticProperty("now") { _ in … }` and `t.staticMethod("random", "in:any") { c in … }`.
- `t.implicit { name, args, labels in … }` resolves `.name` wherever the type is expected.
- `t.anyStatic { c, name in … }` takes members not listed by name (SwiftUI's enum-like types are symbolic: `Edge.Set.all`).

**Instance members:** `t.property(_:_:set:)` and `t.method(_:_:)`, with `t.anyProperty` and `t.anyMethod` for dynamic names.

**Mutating methods:** set `c.mutated = newValue`, and the engine writes it back to where the receiver lives (`array.append`).

**Fallbacks:** `t.fallback("Sequence") { value, interp in … }` makes a type have another type's members, converted on the way. That's how a `String` has `map`.

**Waiting:**

- An `async` method returns `.suspension(KSuspension.async(headless:) { … })` or `KSuspension.callback { ctx, resume in …; return cancel }`.
- A native `AsyncSequence` becomes `for await`-able with `KAsyncSequence.wrapping(name, sequence) { element in kv }`.
- `headless` is what `Kiln.validate` gets instead of waiting. nil means the check stops following that task.
- **Say so, for the checker.** A method, static method, function or property that returns a suspension takes `async: true`: `Kiln.check` then reports a call to it with no `await` (`'Task.sleep' is async: call it with 'await'`). A bridge whose closures may `await` (it starts them as tasks, as `Task {}`, `.task {}`, `.refreshable {}` and `withTaskGroup` do) takes `closuresCanWait: true` (`m.closuresCanWait()` on a modifier). Everywhere else, `Kiln.check` calls an `await` in a closure argument an error, because the engine can't wait there either.
- **An initializer makes its own type.** `Kiln.check` takes `T(…)` to be a `T` and checks the members called on it against `T`'s bridge. A type whose initializer makes something else (`NSDataDetector` makes an `NSRegularExpression`) must have no instance members of its own.

**Observation:** a native `@Observable` object read in a property getter is tracked by SwiftUI, because the app's `body` runs inside the hosting view's real `body`. `RegistryTests.testNativeObservableReadsAreTrackedBySwiftUI` pins this down.

**Adding to another family's type:** `r.extend("URL") { t in … }`. For example, Files adds file URLs to Foundation's `URL`. Two families can't both register `type:URL`. Families register in `KilnFamily`'s order, so a family can only `extend` a type an earlier family declared in `register(into:)`; to add to one a later family declares (Text adds `Range(_:in:)` and `String.utf16` to Language's types, Units formats through Foundation's), override `class func extend(into r: KRegistry)` in the family's class: it runs after every family has registered.

**Value types the engine doesn't know.** Box them, so they compare by value: `.native(.boxed(KBoxed("Measurement", value)))` with a `Hashable` value (`KMeasure`, `KDecimal`, `KNSRange`). Then:

- `typeRef(of:)` is the box's type, so `m.unit == .kilometers` resolves `.kilometers` with that type's `implicit`;
- `t.operator("+") { a, b, line in … }` gives the type its operators (and `"<"` its ordering: `sorted()`, `max()`, `>` and `<=` follow). The engine asks the left operand's type, then the right's, after its own cases; return nil for operands the bridge doesn't take;
- a value conforming to `KDescribable` prints as Swift prints it (`"\(distance)"` is "5.0 km"); a native object (`.native(.object(…))`) can conform too;
- `KFormatting.valueFormatters["Measurement"] = { value, style, interp in … }` makes `.formatted(style)`, `Text(value, format:)` and string interpolation with a format use the type's own formatting;
- a setter or a `mutating` method sets `c.mutated` to the new box, which the engine writes back.

**Nested native types.** `NSTextCheckingResult.CheckingType.link` and `UIImpactFeedbackGenerator.FeedbackStyle.heavy` work when the nested type is registered by its dotted name (`r.type("NSTextCheckingResult.CheckingType", …)`).

## A host bridge

The app hosting Kiln registers its own bridges through the public API, with the same overload rules and errors. Values cross as `KilnValue`. A host bridge is registered once, for the whole process; what's per run, it reaches through the run's context (`call.context`). Here is Shelf's `DB` (`Shelf/Data/DBBridge.swift`), whose store is the run's own:

```swift
// Once, at launch.
Kiln.registerType("DB", notes: "Synced key-value storage: JSON Data under a string key.") { t in
    t.staticMethod("load", "_:string") { call in
        guard let store = call.context.provided(DBSession.self) else { throw call.error("DB isn't available here") }
        return store.value(for: try call.string(0)).map { KilnValue(data: $0.json) } ?? .nil
    }
    t.staticMethod("save", "_:string _:any") { call in
        guard let data = call.value(1)?.data else { throw call.error("needs Data") }
        try call.context.provided(DBSession.self)?.write(…, for: try call.string(0))
        return .void
    }
}

// Each run.
let context = KilnContext(slug: app.slug, name: app.name, defaults: suite, files: KilnFiles(root: folder),
                          capabilities: gate)
context.provide(session)          // what `call.context.provided(DBSession.self)` finds
let result = Kiln.run(source, context: context)
```

`KilnCall` also has:

- `json(_:)`, an app value encoded as `JSONEncoder` would encode it;
- `decode(_:as:)`, JSON decoded into the app's type (`T.self` from `call.type(_:)`);
- `receiver`, `setReceiver(_:)` and `error(_:)`;
- `context`, the run's `KilnContext` (next section).

`KilnValue.async { … }` makes an async member. `Kiln.registerFunction(_:signature:_:)` adds a global function.

Registering a host type again replaces it. Host bridges are in the manifest the running app exports, but not in the checked-in `kiln-manifest.json`, which is Kiln's own.

## The run's context

Every run has a `KilnContext` (PLAN.md §1.7, `Sources/Kiln/Context/`). The host makes one per open of an app and passes it to `Kiln.run(_:context:)`; `Kiln.validate` gets a stub one (`KilnContext.stub()`) unless it's given another, and `Kiln.run(_:)` alone gets `KilnContext.standard()`. A bridge reaches it as `c.context` (`KCall`) or `call.context` (`KilnCall`). It holds:

| | What | A bridge uses |
|---|---|---|
| Identity | `slug`, `name` ("Run Tracker") | for messages and prompts |
| Settings | `defaults`: the app's own `UserDefaults` suite. `@AppStorage` and `UserDefaults.standard` resolve to it | `c.context.defaults` |
| Files | `files`: the app's folder (`KilnFiles`), laid out as an app container: `Documents`, `Library/Application Support`, `Library/Caches`, `tmp` | `try c.context.files.resolve(url)` |
| Host values | anything the host put there with `provide(_:)`: Shelf's `DB` session, a fake sensor | `c.context.provided(FakeMotion.self)` |
| Capabilities | the host's gate for this app (`KilnCapabilityGate`; Shelf's `AppPermissions`) | `c.context.capabilities.request(.location)` |
| Teardown | what stops when the app's screen closes | `c.context.onTearDown { … }` |
| Stub | `isStub`: a check, not a real run | use the fake, write nothing that lasts |
| Errors | `onError`, which the host sets: every check, `body` and runtime error with its line (`KilnError`) | nothing: throw as usual |

### Files

Every path an app names goes through `files.resolve`, which standardizes it (`.` and `..`), follows symbolic links, and throws `KilnFiles.Refusal` for anything outside the folder or not a file URL. `FoundationBridges.file(c, "at")` does that for an argument and turns a refusal into the app's error with its line:

```swift
t.method("startRecording", "to:URL") { c in
    let url = try FoundationBridges.file(c, "to")      // in the app's folder, or "Line 9: …: /etc/x is outside the app's folder"
    …
}
```

`URL.documentsDirectory`, `.applicationSupportDirectory`, `.cachesDirectory`, `.temporaryDirectory`, `FileManager.default.urls(for:in:)`, `Data(contentsOf:)`, `data.write(to:)`, `String(contentsOf:encoding:)` and `text.write(to:atomically:encoding:)` already resolve there (`Bridges/Foundation/FileSystem.swift`). A Foundation error the app can catch goes through `FoundationBridges.thrown(error, c)`, which leaves the folder's real place on the device out of the message. The host's Settings reads `files.usage()`.

### Capabilities, as a suspension

Asking is something `await` waits on. `c.context.capabilities.request(_:)` returns a `KSuspension` that resumes with `.bool(allowed)`:

```swift
// CLLocationManager().requestWhenInUseAuthorization(), then the delegate hears the answer.
t.method("requestWhenInUseAuthorization", "") { c in
    let manager = c.object(KLocationManager.self)
    return .suspension(c.context.capabilities.request(.location))      // `await` resumes with true or false
}

// Or ask inside the bridge's own async work, then start the real thing only if allowed.
t.method("requestLocation", "") { c in
    let context = c.context
    return .suspension(KSuspension.async(headless: { FakeLocation.here.kv }) {
        guard await context.capabilities.ask(.location) else { throw KEThrown(value: KBuiltins.errorValue("Location is off for this app")) }
        return try await RealLocation.once().kv
    })
}
```

- `capabilities.status(.camera)` is the answer without asking (`.notAsked`, `.allowed`, `.denied`), for `authorizationStatus`.
- Headless (`validate`) or in a stub context, the request never waits and nobody is asked: the gate's `answerWithoutAsking` answers at once. `KilnStubCapabilities` (and Shelf's `StubAppPermissions`) allow everything by default and record each request in `requested`.
- Cancelling the waiting task, or tearing the run down, resumes it with `false` and withdraws the host's prompt (`cancelRequests`).
- A host bridge gets the same as a `KilnValue`: `call.context.capabilities.request(.location)`. `capabilities.ask(_:)` is the plain `async -> Bool` form.
- The capabilities are `KilnCapability`: `camera`, `microphone`, `motion`, `location`, `photoLibraryAdd`, the same raw values as Shelf's `Capability`. What iOS doesn't ask about (the photo picker, files, the raw motion sensors) isn't gated.

### Teardown

Whatever a bridge starts that would outlive the screen registers how to stop it:

```swift
let manager = CMMotionManager()
manager.startDeviceMotionUpdates(to: .main) { … }
let token = c.context.onTearDown { manager.stopDeviceMotionUpdates() }
// It stopped by itself (the app called stopDeviceMotionUpdates()): teardown needn't.
token.cancel()
```

`context.tearDown()` (which `KilnResult.tearDown()` calls, and Shelf calls when a card closes) first cancels the run's tasks and timers, then runs the stoppers, last registered first, each once, then withdraws any permission request still waiting. Nothing of the app's code runs after it. A stopper registered after teardown runs at once. `URLSession`'s `dataTask` registers its cancel this way.

### Stubs and fakes

`KilnContext.stub()` is what a check runs with: empty throwaway settings and folder (removed at teardown), a gate that answers at once, `isStub` set. A bridge in a stub context does nothing real: no sensor, no network (requests fail at once, as offline), no prompt. Round 3's fakes go through `provide`: the host (or a test) provides a fake source, and the bridge prefers it:

```swift
let source: MotionSource = c.context.provided(FakeMotion.self) ?? (c.context.isStub ? FakeMotion.still : RealMotion())
```

### Errors

The host sets `context.onError`. It hears each error once, as a `KilnError` with its `phase` (`.check`: the code doesn't parse or has no view; `.body`: a view's `body` failed, so what shows is broken; `.runtime`: an action, a task, a global), `line` and `message`, on the main actor and never during a SwiftUI update. Shelf shows its error screen for `.check` and `.body`.

### Building off the main thread

`Kiln.parse(source)` runs on any thread and returns a `KilnParsedSource`, which `Kiln.run(_:context:)` takes on the main actor. Shelf parses when a finger lands on the icon, so the card's open isn't held up by it.

## Result builders

A bridge that takes builder content of its own (RegexBuilder's `Regex { … }`, §3.3) registers the builder, and code marked with its attribute (`@RegexComponentBuilder`, or a parameter the bridge declares with it) runs through Swift's transform (`Engine/KEBuilders.swift`):

```swift
r.resultBuilder("RegexComponentBuilder", .text) { b in
    b.method("buildBlock") { parts, _, interp in … }               // parts: each statement's value
    b.method("buildEither") { args, labels, _ in … }               // labels: ["first"] or ["second"]
    b.method("buildOptional") { args, _, _ in … }                  // args[0] is .nilValue when the `if` was false
}
```

`interp.builderClosure(closure, .custom(builder))` makes a closure argument run as the builder when it's called. `@ViewBuilder` content is the engine's own (`content` kind), not a registered builder.

## A protocol proxy

PLAN.md §1.5. Native code uses the app's own value as one of its protocols:
SwiftUI draws the app's `Shape`, lays out with its `Layout`, UIKit calls its
delegate, a share sheet asks its `Transferable` for data. The registry
declares the protocol, its requirements and a **proxy**: a native type that
conforms to the real protocol and forwards each requirement to the app's
member (`Engine/KEProxies.swift`).

### Declaring one

```swift
r.protocolBridge("Layout", .layout,
                 requirements: ["sizeThatFits(proposal:subviews:cache:)", "placeSubviews(in:proposal:subviews:cache:)",
                                "makeCache(subviews:)?", "animatableData?"],
                 support: .full, notes: "Your own layout: …") { app in
    KLayoutProxy(app: app)
}
```

- **Requirements** are written as the app writes them. `?` marks one with a
  default (or an optional one), `static ` a static member, `async ` one that
  waits: `"static transferRepresentation"`, `"async perform()"`,
  `"init(configuration:)"`. A type that adopts the protocol without a required
  one is an error with the type's line (`'Wave' doesn't conform to 'Shape': it
  has no path(in:)`), and `Kiln.check` and the manifest (`requirements`,
  `proxy`) read the same list.
- **The proxy** gets a `KAppValue` and returns the native value (an
  `AnyShape`, a `Layout`, an `AnyView`, an object). `interp.proxy(for: value,
  as: "Layout")` makes it for a bridge that took the app's value, or nil when
  the value's type doesn't adopt the protocol.
- A family can give a protocol another family declared its proxy:
  `r.proxy("Shape") { app in … }`.

### `KAppValue`

The app's value as the proxy holds it. A struct is a copy, as Swift copies it
into a generic; a class instance is shared.

| | |
|---|---|
| `app.implements("makeCache", labels: ["subviews"])` | the app's type has it (its own, or from an `extension` it adopts) |
| `var a = app; try a.call("sizeThatFits", args, labels: ["proposal", "subviews", "cache"])` | a synchronous requirement, with its own step budget; a `mutating` one changes `a` |
| `a.callReporting(…, fallback:)` | the same where SwiftUI calls it and nothing can throw: an error is reported with its line |
| `app.get("title")`, `a.set("title", v)`, `app.getStatic("readableContentTypes")` | properties, computed ones too |
| `try await app.callAsync("perform", [], labels: [])` | an `async` requirement: a VM task on the main actor, awaited; cancelling the Swift task cancels it |
| `interp.awaitValue(v)`, `interp.callAwaiting(closure, args)` | the same for a closure the app passed (a `DataRepresentation`'s `exporting:`) |

Pass values as Kiln's (`KV`). An `inout` parameter (a layout's `cache`) is a
`.binding(KBinding(get:set:))`.

**Threads.** The app's code runs on the main thread, and SwiftUI calls some
requirements elsewhere: it interpolates `animatableData` on its render thread,
and may lay out there while it animates. So:

- a proxy's `animatableData` is a kept `KAnimVector`, read once from the app
  (`KAnimatable.data(app)`) and given to the app's value when its code runs
  (`KAnimatable.applied(app, data)`); never the app's getter on each frame;
- the app's code runs in a view's `body` where it can (`KShapeHost` draws the
  app's shape in an `Animatable` view, so its `path(in:)` runs on the main
  thread each frame);
- a requirement that can be called off the main thread waits for it with
  `KDelegates.onMain { … }`.

### One of each kind

**A SwiftUI protocol** (`Drawing/Animatable.swift`, `Layout/CustomLayout.swift`, `Core/Core.swift`):

```swift
struct KModifierProxy: ViewModifier, Animatable {
    let app: KAppValue
    var data: KAnimVector                     // KAnimatable.data(app), at init
    nonisolated var animatableData: KAnimVector { get { data } set { data = newValue } }
    func body(content: Content) -> some View {
        // The app's body(content:) with SwiftUI's content, in a host that keeps its @State.
        KModifierHost(value: KAnimatable.applied(app, data).structValue!, interp: app.interp, content: AnyView(content))
    }
}
```

SwiftUI's own content goes to the app as `KNativeContent.value(AnyView(content))`,
a view the app modifies like any other.

**A representable and its coordinator** (`Core/Representables.swift`): the
app's `UIViewControllerRepresentable` is shown by `KControllerRepresentable`,
which calls the app's `makeCoordinator()`, `makeUIViewController(context:)`
and `updateUIViewController(_:context:)`. What the app returns must be on the
**allowlist**. To allow a controller, bridge its type (the members models
write) and declare it:

```swift
r.type("UIImagePickerController", .camera) { t in … }          // init, sourceType, delegate, dismiss
#if os(iOS)
r.representableController(UIImagePickerController.self, "UIImagePickerController")
#endif
```

`r.representableView(UIVisualEffectView.self, "UIVisualEffectView")` is the
same for `UIViewRepresentable`. Register the type's declaration on every
platform (the manifest is written on the Mac), with the UIKit inside
`#if os(iOS)`.

**A delegate** (`Engine/KEDelegates.swift`, `Camera/Camera.swift`): an
Objective-C delegate protocol needs only its declaration; the proxy is
generic (`KilnForwardingProxy`, an `NSProxy` in the `KilnObjC` target that
conforms at run time to every delegate protocol the app's class adopts):

```swift
r.delegateProtocol("CLLocationManagerDelegate", .location,
                   requirements: ["locationManager(_:didUpdateLocations:)?", "locationManager(_:didFailWithError:)?"])
```

The bridge that takes the delegate sets the proxy and keeps it alive
(delegates are weak):

```swift
t.property("delegate", { _ in .nilValue }, set: { c in
    guard let manager = c.object(CLLocationManager.self), let proxy = KDelegates.proxy(for: c.args[0], c.interp) else { … }
    manager.delegate = unsafeBitCast(proxy, to: CLLocationManagerDelegate.self)
    KDelegates.retain(proxy, by: manager)
})
```

- Each requirement's selector is derived from its Swift name
  (`locationManager(_:didUpdateLocations:)` is `locationManager:didUpdateLocations:`);
  `spec.selectors[…]` overrides one Swift renames.
- Arguments arrive converted by `KNativeValues.kv(from:)`: strings, numbers,
  arrays, dictionaries, URLs, dates, `Data`, errors, and objects of classes
  registered with `r.nativeClass(CLLocation.self, "CLLocation")`.
  `spec.arguments(requirement) { args, interp in … }` converts one itself
  (the picker's `info` keys become `.originalImage`).
- `respondsToSelector:` is true only for what the app implements, and after
  teardown the proxy answers nothing.
- A Swift-only protocol (`DataScannerViewControllerDelegate`) subclasses
  `KAppDelegateObject`, conforms, and forwards each method with
  `forward("dataScanner(_:didTapOn:)", args)`; declare it as the protocol's proxy.

**`Transferable`** (`Sharing/Transferable.swift`): the app's
`transferRepresentation` runs through `TransferRepresentationBuilder`, and
`KTransferItem` is the native `Transferable`. A bridge that shares or exports
takes `interp.proxy(for: v, as: "Transferable") as? KTransferItem`; one that
pastes, drops or imports calls
`KTransferables.importValue(type, data:, contentType:, interp)`.
`FileDocument` is the same shape (`Files/Files.swift`):
`KFileDocuments.document(for:)` for `.fileExporter`, `read(_:data:contentType:)`
for an importer.

**An `async` requirement**: inside Kiln, `try await app.callAsync(…)`. A host
declares its protocol and awaits the app's value the same way:

```swift
Kiln.registerProtocol("Greeter", requirements: ["async greet(name:)"])
Kiln.registerFunction("greetWith", signature: "_:any") { call in
    guard let g = call.adopter(0, as: "Greeter") else { throw call.error("needs a Greeter") }
    return .async { try await g.callAsync("greet(name:)", [KilnValue(string: "Ann")]) }
}
```

An error the app's code throws reaches the caller (and the app's `catch`, if
the call came from the app).

### Testing one

`ProxyTests` has the patterns: call the proxy directly (`KUserShape(app:)`'s
`path(in:)`, `animatableData` set as SwiftUI would), mount the app in a
hosting view for a view or layout, and a missing requirement's error. Anything
UIKit is tested in Shelf's `FeatureFixtureTests`, on the simulator.

## Protocols, environment values, property wrappers

These are declarations, which the manifest and the checker read:

- `r.protocolBridge("Identifiable", .language, requirements: ["id"])`, with no proxy: the engine implements it. With a proxy, see [a protocol proxy](#a-protocol-proxy). `Kiln.check` reports an app type that adopts the protocol and leaves out a requirement. One with a default in Swift ends in `?` (`"errorDescription?"`, `"animatableData?"`), and isn't required.
- `r.environmentValue("dismiss", .environment) { interp in … }` gives the value `@Environment(\.dismiss)` reads before SwiftUI's arrive.
- `r.liveEnvironment("editMode", .navigation, read: { env, interp in … }, write: { view, value, c in … })` reads the value from SwiftUI's own environment where the view is shown: a view (or `ViewModifier`, or style) with such an `@Environment` property is hosted inside a reader of `EnvironmentValues` (`KLiveEnvironment`), and the others don't depend on the whole environment. `write` is what `.environment(\.editMode, $mode)` does.
- `r.environmentValue("dynamicTypeSize", .text, value: { _ in … }, read: { env, interp in … }, write: { env, value, interp in … })` is the same, for a value that `.environment(\.key, v)` and `transformEnvironment` set in place (`writeEnvironment`): every SwiftUI environment value Round 1 bridges is in `Bridges/Environment/Values.swift`. Enum-like values are symbols the app compares with (`.compact`, `.dark`); an ordered one is a `KBoxed` with an `order` (`dynamicTypeSize >= .accessibility1`).
- `r.wrapper("State", .environment)` declares a wrapper the engine implements (`KViewStorage`).
- `r.macro("Entry", .core)` declares a macro the engine reads (`KEMacros.swift`); the manifest lists it as `macro:Entry`.
- `r.implicitProperties["isScrolling"] = { base, args in … }` gives SwiftUI's symbolic values a property (`phase.isScrolling` on `.idle`, `mode.isEditing` on `.active`); return nil for a value that isn't yours.

**An app's own control style** (`struct Pressable: ButtonStyle`) goes through a native style whose `makeBody(configuration:)` calls the app's, with the configuration as a value (`Bridges/Controls/CustomStyles.swift`): `configuration.label` is SwiftUI's own view, `configuration.isOn` a binding, and `Toggle(configuration)` shows the default. `ButtonStyle`, `PrimitiveButtonStyle`, `ToggleStyle`, `LabelStyle`, `ProgressViewStyle`, `GaugeStyle`, `GroupBoxStyle`, `LabeledContentStyle`, `DisclosureGroupStyle`, `ControlGroupStyle`, `FormStyle`, `MenuStyle`, `TextEditorStyle`, `DatePickerStyle`, `NavigationSplitViewStyle` and `ArrangementViewStyle` work this way; the styles whose requirements SwiftUI keeps private can't be adopted by any app.

**Closures that aren't view content.** `Kiln.validate` calls every closure a modifier takes, as content, with no arguments. A closure that gets something (`alignmentGuide`'s `computeValue` gets dimensions, `onScrollGeometryChange`'s `of:` a geometry) says what with `m.probe { label, interp in [sample] }`, by its label (nil for a trailing closure; the bridge's `sampleArgs`). A bridge whose closures need more than that (a drag's `onChanged` gets a drag value, `updating` an `inout` state and a transaction, a `Canvas` renderer a context and a size, an action is fired rather than shown) takes the whole hook, `m.probe { base, args, interp in [KProbeCall(fn:args:use:)] }` (or `v.probe` on a view): `base` is what the modifier is on (the gesture, for `onChanged`), `use: .action` fires the closure after the walk, `.content` walks the views it makes. The transcript (`Tools/diff.sh`) runs the same calls.

**`inout` closure parameters.** Pass `.binding(.inOut(get:set:))`: assigning the parameter in the app's closure writes through (`updating`'s `state`, `transformEnvironment`'s value, `Canvas`'s `context`).

### SwiftUI's environment, namespaces and focus (`KEHostInputs.swift`)

A view whose type reads a live environment value, or has `@Namespace`, `@FocusState`, `@AccessibilityFocusState` or a focused value, is hosted inside `KHostInputs`: one real `@Environment(\.self)`, `@Namespace`, `FocusState<KV?>` and `AccessibilityFocusState<KV?>` per host, which observes the view's storage so its `@State` still redraws it. The app's properties map onto them:

- each `@Namespace` is the host's namespace with the property's name (`KNamespaceID`); a bridge gets it with `c.interp.namespace(c["in"])` and ids it with `KNamespacedID(slot:id:)` (`matchedGeometryEffect`, `glassEffectID`, `accessibilityRotorEntry`);
- each `@FocusState` reads and writes the host's focus state as `(property, value)`; `$field` carries a `KFocusProjection` in `KBinding.native`, which `.focused` and `.defaultFocus` pass to SwiftUI;
- `@FocusedValue`, `@FocusedBinding` and `@FocusedObject` go through eight real `FocusedValues` slots, one per key name (`KFocusSlots`).

### Gestures, Canvas and charts

- **A gesture** is a description (a primitive with modifiers, as a view); `KGestureBuilder` makes it SwiftUI's `AnyGesture<KV>`, every kind's value mapped to Kiln's, so `onChanged`, `updating`, `simultaneously(with:)` and the rest compose whatever the kinds. `@GestureState` resets through a real `GestureState` in `KGestureAttach`.
- **A `Canvas`** renderer runs in a view's body and records into `KCanvasRecording`; SwiftUI's `Canvas` replays it. `GraphicsContext` is a value (`KGCState`), so a copy's transform stays on the copy.
- **A chart's marks** become Swift Charts' own, erased to `AnyChartContent` (`KChartBuilder`), built for the axes' plottable types (`KPlotType`).

## Foundation and the standard library

Round 2C (PLAN.md §3) made Foundation, Combine and the standard library behave as compiled Swift does, checked by the corpus. What that means for a bridge:

- **Add a corpus entry for it.** `Tests/Corpus/<Family>.corpus` (format in `Registry/KilnCorpus.swift`): one line per call, `Calendar.date(from:) :: Calendar.current.date(from: …)!`, then `Tools/corpus/oracle.py --write <id>` compiles it with swiftc and writes the value compiled Swift prints after `=>`. `CorpusTests` then holds Kiln to it, and the manifest and `COVERAGE.md` count it. Mark one that needs UIKit `[ios]` (Shelf's `KilnCorpusTests` runs it on the simulator, and you write its value by hand), and one Kiln can't do yet `[gap]` with a won't-do entry or a PLAN.md note.
- **Real signatures, not `nil`.** A loose bridge (`t.method("date") { c in … }`) takes any labels, so the checker can't report a form it doesn't have and the manifest can't list its forms (`anyLabels`). Write every form: `t.method("date", "byAdding:any value:number to:any wrappingComponents:bool?")`. Read arguments with `c["label"]` (it follows the overload's binding, so a trailing closure is found by its parameter's label), not `c.arg("label")` (the label as written).
- **`first: true`** puts a precise form ahead of an older loose one (`t.method("firstIndex", "where:closure", first: true)`): overloads are tried in order, and a loose one takes everything.
- **An unknown static member is an error.** `Type.name` that the type's bridge doesn't have stops the code with its line (`requireSymbolic`), as `Kiln.check` reports it. A type whose bridge lists no static members stays symbolic (`Edge.Set.all` is passed on by name), and so does a type only signatures name. So a type with some statics must list every static an app may write.
- **Value types.** Box them (`KBoxed`) with a `Hashable` value; conform it to `KDescribable` to print as Swift prints it, to `KNumericBox` (`intValue`, `doubleValue`) to read as a number wherever one is read (`UInt8`, `Int32`), and to `KNativeSequence` to loop with `for in`, `Array(x)` and the `Sequence` methods (`Data`'s bytes, a digest, SIMD's scalars). `t.operator("+")` gives it arithmetic (asked before the engine's own for a boxed operand), `"prefix-"` and `"prefix~"` its prefix operators.
- **Literals.** `r.addLiteralCoercion("UInt8") { v, type in … }` makes a literal or a plain number the type's value where the type is expected: `let b: UInt8 = 200`, a `[UInt8]` array, `let v: SIMD2<Double> = [1, 2]`, `let d: Duration = .seconds(2)`. `type` is the full written type, with its generic arguments.
- **Generic arguments.** `SIMD2<Double>(1, 2)` and `PassthroughSubject<Int, Never>()`: the initializer reads `c.interp.constructingGenerics` (`[KETypeRef]`).
- **Format styles** are kept as the calls made on them (`KFormat.steps`) and replayed onto Foundation's own style for the value being formatted (`Bridges/Foundation/FormatStyles.swift`): to support a style call, add its case to the replay; one it doesn't know is an error (`KFormatStyles.Unsupported`), never dropped. `KFormatStyles.symbol(_:)` reads a symbol whether it arrived as `.implicit` or as a context-free style (`.currency`, `.percent`).
- **Standard-library types written in Swift.** `Result` and `AnyIterator` are Swift source (`KSwiftPrelude`, `Bridges/Language/Stdlib.swift`), added to an app that names them and doesn't declare its own: the engine runs them as the app's types, and `Kiln.check` reads (but doesn't check) them. Prefer this for a type whose behavior is plain Swift.
- **Combine** publishers are `KPub` (`Bridges/Concurrency/Combine.swift`): a bridge that publishes makes a `KSubject` or `KMadePub { subscriber, token in … }`; `KCombineBridge(pub:)` is the real Combine publisher SwiftUI's `.onReceive` takes.

## What the checker and the prompt read

`Kiln.check` (PLAN.md §1.8) and Shelf's prompt (§7) are built from the registry, so a bridge reaches both the day it's registered. What each needs from it:

| Declare | So that |
|---|---|
| Every form models write, as a signature | `check` accepts it, and reports labels no form takes, listing the forms there are. |
| `support: .stub`, or `m.stub([…])` | `check` warns (`.symbolEffect is accepted but has no effect yet`, with the notes), and the prompt lists it under "Accepted, but they do nothing yet". |
| `support: .partial` with `notes` | The prompt quotes the notes under the family. Write them for app authors: what works, what doesn't, what to use instead, in one or two sentences. A `full` symbol's notes stay out of the prompt. |
| `async: true`, `closuresCanWait` | `check` reports a missing `await`, and an `await` where nothing can wait. |
| Protocol `requirements` | `check` reports a type that adopts the protocol without them. |
| The family | A family with no supported symbol is listed under "Not in Kiln yet" with its `KilnFamily.summary`; its first bridge moves it to "What works", and Shelf's `everyPromptSectionHasAFixture` then wants a fixture whose `// Covers:` line names it. Keep the summary true. |
| `KilnFamily.promptLine` | "What works" says the family in that one hand-written line instead of listing every name: for a family that's nearly all of SwiftUI's, where the list would be long. Name what an author would otherwise doubt (iOS 26 and 27 additions, the forms that differ); keep it true as bridges change. Partial symbols' notes still follow it. |

Language features that don't work yet are `KLanguageGaps` probes (`Registry/KLanguageGaps.swift`): each gap has its sentence for authors and a small app that prints "ok" when the feature works. `Tools/manifest.sh` runs them and writes the failing ones into the manifest, so a fixed gap leaves the prompt by itself.

`check` is conservative: where it can't tell a value's type, it says nothing. So a bridge never needs to declare more to avoid a false error. But `CheckCorpusTests` must stay at zero errors on every app that runs, and a new example app is added to the corpus by putting it in `Examples/` or `fixtures/apps/`.

## After adding a bridge

1. **Tests.** Add a test for each bridge: the arguments decode, the overloads resolve, the view builds, and a wrong call's error reads correctly. `RegistryTests` has the patterns.
2. **The corpus**, for Foundation and the standard library: an entry per call, its value from `Tools/corpus/oracle.py --write` (see "Foundation and the standard library" above).
3. **The manifest.** Run `Tools/manifest.sh`, which rewrites `kiln-manifest.json` (`testManifestIsCurrent` fails until you do), with the language gaps and the won't-do list. Then run `Tools/coverage.sh`, which rewrites `COVERAGE.md`. Shelf bundles the manifest: its prompt changes with it, and `PromptsTests` checks the result.
4. **The differential.** `Tools/diff.sh` should still be identical on every input, or the difference goes in `Tools/diff-expected.txt` with a reason.
5. **The bench.** `Benchmarks/run.sh` must show no input more than 10% slower.

## Gotchas

- **Nested types' extensions.** `extension Notification.Name { static let … }` is found by the full name and the last part (`builtinExtensions`), so `.planChanged` resolves where `Notification.Name` is expected: declare the kind as `Notification.Name`, not `any`.

- **Helper functions need `@MainActor`.** A local function inside a `register` closure isn't main-actor isolated in Swift 5 mode, so write `@MainActor func f(_ c: KCall)`, or a `static func` on the family class.
- **View-builder closures can't hold `for`, `guard` or `continue`.** Move that work into a `static func`.
- **Kinds change evaluation.** Typing an argument that used to be `any` changes what implicit members resolve to: with no expected type, a lone app enum with a `.leading` case would win. Run the differential.
- **Unknown names are errors.** A bridge that takes fewer labels than SwiftUI's declaration turns working code into an error. List every form models write.
