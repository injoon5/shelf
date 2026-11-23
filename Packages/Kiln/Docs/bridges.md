# Adding a bridge

Everything native an app can name in Kiln is a **bridge** in the registry (PLAN.md §1.4): views, modifiers, types (with their initializers, static members, properties and methods), global functions, protocols, environment values and property wrappers. The engine knows no names of its own. It asks the registry, and anything the registry doesn't have is an error with the author's line.

This page is the guide for adding one. It has one worked example per kind:

- [a view](#a-view);
- [a modifier](#a-modifier);
- [a type with an `async` method](#a-type-with-an-async-method);
- [a host bridge](#a-host-bridge).

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
    // `try await page.callJavaScript("…")`: an async method returns what `await` waits on.
    t.method("callJavaScript", "_:string") { c in
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

**Observation:** a native `@Observable` object read in a property getter is tracked by SwiftUI, because the app's `body` runs inside the hosting view's real `body`. `RegistryTests.testNativeObservableReadsAreTrackedBySwiftUI` pins this down.

**Adding to another family's type:** `r.extend("URL") { t in … }`. For example, Files adds file URLs to Foundation's `URL`. Two families can't both register `type:URL`.

## A host bridge

The app hosting Kiln registers its own bridges through the public API, with the same overload rules and errors. Values cross as `KilnValue`. Here is Shelf's `DB` in §1.7:

```swift
Kiln.registerType("DB", notes: "Synced key-value storage: Data under a string key.") { t in
    t.staticMethod("load", "_:string") { call in
        store.data(for: try call.string(0)).map { KilnValue(data: $0) } ?? .nil
    }
    t.staticMethod("save", "_:string _:any") { call in
        guard let data = call.value(1)?.data else { throw call.error("needs Data") }
        store.set(data, for: try call.string(0))
        return .void
    }
    t.staticMethod("remove", "_:string") { call in
        store.remove(try call.string(0))
        return .void
    }
}
```

`KilnCall` also has:

- `json(_:)`, an app value encoded as `JSONEncoder` would encode it;
- `decode(_:as:)`, JSON decoded into the app's type (`T.self` from `call.type(_:)`);
- `receiver`, `setReceiver(_:)` and `error(_:)`.

`KilnValue.async { … }` makes an async member. `Kiln.registerFunction(_:signature:_:)` adds a global function.

Registering a host type again replaces it. Host bridges are in the manifest the running app exports, but not in the checked-in `kiln-manifest.json`, which is Kiln's own.

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

## Protocols, environment values, property wrappers

These are declarations, which the manifest and the checker read:

- `r.protocolBridge("Shape", .drawing, requirements: ["path(in:)"])`. §1.5 adds the proxy: a native class that forwards each requirement to the app's value (`KProtocolBridge.proxy`).
- `r.environmentValue("dismiss", .environment) { interp in … }` gives the value `@Environment(\.dismiss)` reads before SwiftUI's arrive.
- `r.wrapper("State", .environment)` declares a wrapper the engine implements (`KViewStorage`).

## After adding a bridge

1. **Tests.** Add a test for each bridge: the arguments decode, the overloads resolve, the view builds, and a wrong call's error reads correctly. `RegistryTests` has the patterns.
2. **The manifest.** Run `Tools/manifest.sh`, which rewrites `kiln-manifest.json` (`testManifestIsCurrent` fails until you do). Then run `Tools/coverage.sh`, which rewrites `COVERAGE.md`.
3. **The differential.** `Tools/diff.sh` should still be identical on every input, or the difference goes in `Tools/diff-expected.txt` with a reason.
4. **The bench.** `Benchmarks/run.sh` must show no input more than 10% slower.

## Gotchas

- **Helper functions need `@MainActor`.** A local function inside a `register` closure isn't main-actor isolated in Swift 5 mode, so write `@MainActor func f(_ c: KCall)`, or a `static func` on the family class.
- **View-builder closures can't hold `for`, `guard` or `continue`.** Move that work into a `static func`.
- **Kinds change evaluation.** Typing an argument that used to be `any` changes what implicit members resolve to: with no expected type, a lone app enum with a `.leading` case would win. Run the differential.
- **Unknown names are errors.** A bridge that takes fewer labels than SwiftUI's declaration turns working code into an error. List every form models write.
