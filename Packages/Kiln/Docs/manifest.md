# `kiln-manifest.json`

What Kiln supports, as data. §1.4's bridge registry exports it, and three things read it:

- **the coverage report** (`Tools/coverage.sh`, PLAN.md §1.9), which compares it with the iOS SDK and writes `COVERAGE.md`;
- **Shelf's prompt** (§7), which builds its "What works" section from the symbols and their `notes`;
- **`Kiln.check`** (§1.8), and later a server-side symbol check (PLAN.md, Later).

The registry writes it to `Packages/Kiln/kiln-manifest.json`, and it's checked in. The coverage tool reads it; `Tools/manifest.sh` regenerates it from the registry, and `RegistryTests.testManifestIsCurrent` fails when it's stale.

The schema is defined in code in `Tools/coverage/Sources/CoverageKit/Manifest.swift`. This page describes it.

## Example

```json
{
  "schemaVersion": 1,
  "interim": false,
  "generator": "kiln-registry",
  "description": "Kiln 0.3.0",
  "symbols": [
    {
      "id": "view:DatePicker",
      "kind": "view",
      "name": "DatePicker",
      "family": "Controls",
      "support": "partial",
      "introduced": "13.0",
      "overloads": [
        { "labels": ["_", "selection", "displayedComponents"] },
        { "labels": ["_", "selection", "in", "displayedComponents"] }
      ],
      "notes": "Every style, including `.graphical`. `selection` must be a `@State` `Date`.",
      "source": "Sources/Kiln/Bridges/Controls/DatePicker.swift"
    },
    {
      "id": "modifier:ToolbarContent.visibilityPriority",
      "kind": "modifier",
      "name": "visibilityPriority",
      "owner": "ToolbarContent",
      "family": "Navigation",
      "support": "full",
      "introduced": "27.0",
      "overloads": [ { "labels": ["_"], "receiver": "ToolbarContent" } ]
    },
    {
      "id": "style:DatePickerStyle.graphical",
      "kind": "style",
      "name": "graphical",
      "owner": "DatePickerStyle",
      "family": "Controls",
      "support": "full",
      "overloads": []
    }
  ]
}
```

## Top level

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | int | `1`. The coverage tool refuses any other value. Bump it on a breaking change and update `Manifest.currentSchemaVersion`. |
| `interim` | bool | `true` only for the stand-in built from the 0.2.1 switch files. The registry writes `false`. |
| `generator` | string | `kiln-registry`, or `coverage/interim-switch-scan`. |
| `description` | string? | Free text, such as Kiln's version. |
| `symbols` | array | One entry per symbol, sorted by `id`. |

## A symbol

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `<kind>:<owner.>name`, matching the coverage report exactly (see below). The join key. |
| `kind` | string | `view`, `modifier`, `style`, `content`, `gesture`, `member`, `environment`, `wrapper`, `protocol`, `type` or `macro`. |
| `name` | string | The Swift name: `DatePicker`, `padding`, `graphical`, `dismiss`, `State`. |
| `owner` | string? | For `style` and `member`, the protocol or type (`ButtonStyle`, `Animation`). For a `modifier` on anything but a view, its receiver protocol (`ToolbarContent`, `ChartContent`, `Gesture`, `TabContent`). Omitted otherwise. |
| `family` | string | The registry folder it lives in. One of the families in `Tools/coverage/families.json`: Controls, Layout, Lists, Navigation, Gestures, Drawing, Charts, Haptics, Sharing, Text, Units, Audio, Web, Files, Photos, Camera, Motion, Location, Vision, Intelligence, Widgets, plus Core, Focus & Keyboard, Environment, Accessibility, Scenes and Chart3D. The report files symbols by `families.json`, not by this field, so a disagreement only affects the prompt. |
| `support` | string | `full`: every listed overload behaves as in SwiftUI. `partial`: some forms work, and `notes` says which. `stub`: accepted so the code runs, but it has no effect (counts as missing). |
| `introduced` | string? | The minimum iOS version Kiln offers it on, as `"17.0"`. Usually the SDK's. Later if the bridge needs it. |
| `overloads` | array? | The overloads that are bridged. `null` or omitted means "not enumerated" (the interim manifest does this). `[]` means a property or bare member with no arguments. |
| `notes` | string? | For **app authors**: limits, and what to use instead. One or two sentences, in Markdown. The prompt quotes it. |
| `source` | string? | For **maintainers**: the file that implements it. |

### An overload

| Field | Type | Meaning |
|---|---|---|
| `labels` | [string] | Argument labels in order, `_` for an unlabelled one. A trailing closure keeps its label (`content`). `.padding(.horizontal, 8)` is `["_", "_"]`. |
| `receiver` | string? | For modifiers, what it's bridged on: `View`, `Shape`, `InsettableShape`, `Text`, `Image`, `ToolbarContent`, `ChartContent` and so on. Omitted means any receiver. |
| `introduced` | string? | When this overload needs a later iOS than the symbol. |
| `notes` | string? | As for the symbol, for this form only. |

The coverage report counts an SDK overload as covered when a manifest overload has the same `labels` and either no `receiver` or the same one. It shows overload coverage only for symbols that list overloads.

## Ids

The id scheme is the coverage tool's. `coverage.json` lists every SDK symbol's id, so the registry can be checked against it.

| Kind | Id | What it covers |
|---|---|---|
| `view` | `view:DatePicker` | A public type that conforms to `View`, including shapes and gradients. The overloads are its initializers. |
| `modifier` | `modifier:padding` | Every instance method named `padding` on `View`, `Shape`, `InsettableShape`, `Text`, `Image`, `DynamicViewContent` or `ModifiedContent` that returns a view, `Self`, or a shape. |
| | `modifier:ToolbarContent.visibilityPriority` | The same, on another receiver: `ToolbarContent`, `TabContent`, `ChartContent`, `Chart3DContent`, `Gesture`, `Scene`, `TableColumnContent`, `TableRowContent`. |
| `style` | `style:ButtonStyle.borderedProminent` | A static member of a `*Style` protocol (`extension PrimitiveButtonStyle where Self == …`). `Primitive` is dropped, so `.buttonStyle(.borderedProminent)` and `.buttonStyle(.glass)` share the `ButtonStyle` owner. |
| `content` | `content:BarMark`, `content:ToolbarSpacer`, `content:Tab` | A type that's toolbar, tab, chart, axis, table, keyframe, slider-tick, rotor or scene content rather than a `View`. |
| `gesture` | `gesture:DragGesture` | A type conforming to `Gesture`. |
| `member` | `member:Animation.spring`, `member:ShapeStyle.ultraThinMaterial`, `member:Font.title` | Static members of `ShapeStyle`, `Color`, `Font`, `Animation`, `AnyTransition`, `Transition`, `ContentTransition`, `ScrollTargetBehavior`, `NavigationTransition`, `PresentationSizing`, `PresentationDetent`, `ToolbarItemPlacement`, `SensoryFeedback` and `Glass`. |
| `environment` | `environment:dismiss` | A property of `EnvironmentValues`, as `@Environment(\.dismiss)`. |
| `wrapper` | `wrapper:State` | A `@propertyWrapper` type. |
| `protocol` | `protocol:Layout`, `protocol:ButtonStyle` | A protocol an app's own types adopt (through §1.5's proxies). |
| `type` | `type:Animation`, `type:LinearGradient` | Other types models write by name: shape styles, transitions, `Font`, `Angle`, `GridItem`, `NavigationPath` and so on. |
| `macro` | `macro:Entry` | `@Entry`, `@Animatable`, `@Previewable`, `#Preview`. |

Ids the SDK doesn't have (Kiln-only helpers such as `view:UserShape`, or Swift types such as `type:Date`) are allowed. The report lists them under "In the manifest, not in the SDK" and doesn't count them.

## What §1.4 must export

To replace the interim manifest, the registry writes `Packages/Kiln/kiln-manifest.json` with `interim: false` and `generator: "kiln-registry"`, and:

1. **One symbol per bridge**, with the ids above. A view bridge is `view:`, `content:` or `gesture:`, depending on what the SDK type conforms to. A modifier on a non-view receiver carries its `owner`. A style is `style:<Protocol without Primitive>.<member>`.
2. **`overloads` for every view and modifier**: the label lists each bridge accepts, with `receiver` for modifiers. That turns on overload coverage, which is what tells `swipeActions` on a `List` row from `swipeActions` on any view in iOS 27.
3. **`support`**: `full` only when every listed overload behaves as in SwiftUI. Anything accepted and ignored is `stub`.
4. **`notes`** wherever an author could be surprised. The prompt quotes them.
5. **`family`**: the registry's folder name.
6. Write it from a test or a command, not by hand, and keep it sorted and pretty-printed so diffs are readable. `Manifest.encoded()` in CoverageKit does both. A test that fails when the file is stale keeps it honest.

Then delete `Tools/coverage/kiln-manifest.interim.json`, run `Tools/coverage.sh`, and commit the new `COVERAGE.md`. The interim scanner (`EngineScanner.swift`, `InterimManifest.swift`) can go when the switch files do (§1.11).

## The interim manifest

Until §1.4, the coverage tool built a stand-in from the 0.2.1 switch files (`EngineScanner.swift`, `InterimManifest.swift`, `Tools/coverage/kiln-manifest.interim.json`). The registry replaced it: the switch files, the scanner and the interim file are gone, and the coverage tool now needs `kiln-manifest.json` (`Tools/manifest.sh` writes it). What the interim scan counted as supported and the registry doesn't list is deliberate: `.dragToMove` (the old dialect), `Chart3DContent.symbol` (a name match, not a bridge), and the engine-only `UserShape` and `PathShape`.
