# Shelf

An iPhone Home Screen for apps you make yourself.

Every app on Shelf is a single SwiftUI file that a model wrote for you. The files live on [ij5.dev](https://ij5.dev). Shelf syncs them to the phone, shows them as icons on a Springboard-style Home Screen, and runs them on the device with [Kiln](https://github.com/haplollc/Kiln), an interpreter for Swift. There's no compiler, no Xcode project per app, and no App Store. Describe an app, and a minute later it's an icon you can tap.

Shelf needs iOS 27.

## How it works

1. **Make.** Tap **New App** (top left in edit mode, or on an empty Home Screen), describe the app, and copy the prompt Shelf writes into any chat model or coding agent. The prompt tells the model exactly what Kiln can run.
2. **Install.** Either the agent installs the app itself, with a one-time key in the prompt (`PUT /api/apps/<slug>`), or you paste the model's reply back into Shelf, try it in a live preview, and tap Install.
3. **Sync.** Shelf keeps a copy of every app's source on the phone, so the library works offline, and syncs with ij5.dev on launch, on returning to Shelf when the last sync is stale, and from **Sync Now** in Settings.
4. **Run.** Tapping an icon runs the source through Kiln. The app opens as a card that grows out of its icon, and closes with a swipe up from the bottom edge or a drag down from the status bar.
5. **Keep data.** Apps save through `DB`, a small key-value store Shelf provides. It works offline and syncs to your other devices through ij5.dev. `@AppStorage` is for preferences that wouldn't matter if lost.

**Changing an app:** long-press its icon for **Change…** (the same flow, with the current source in the prompt), **Reload App**, **Copy Source**, and **Revert** to the version before the last change.

**What an app can use:** the list is the prompt itself, in [Shelf/Resources/Prompts/new.md](Shelf/Resources/Prompts/new.md), under "What works" and "What doesn't work". Every section there has a matching app in [fixtures/apps/](fixtures/apps/) that has to run and draw, so the list stays true.

## What's next

[PLAN.md](PLAN.md) starts with Shelf itself: an audit of how the Home Screen behaves, moving the Home Screen to UIKit and Core Animation (the sheets stay SwiftUI), search rebuilt as App Library's list, deleting apps, Automatic/Light/Dark icons in place of Clear, the dock's shape, a card that stays on screen during a swipe up, and a better launch screen. Then it takes Kiln into this repo and rebuilds it:

- **The rebuild:** one engine instead of two, real `async`, and a registry of bridges that also drives the prompt and a coverage report.
- **Then, in rounds:**
  - the rest of SwiftUI;
  - haptics, sharing, text parsing, units, audio, `WebView`, `Chart3D` and WebSockets;
  - files, photos, the camera, motion and location;
  - Vision and Foundation Models;
  - widgets on Shelf's Home Screen, written with WidgetKit's API.

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./Scripts/bootstrap.sh     # fetches Kiln 0.2.1, applies Vendor/kiln-0.2.1.patch, generates Shelf.xcodeproj
open Shelf.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't committed. Change `project.yml`, not the project, and run the bootstrap again.

**On a phone:** put your team in `Config/Local.xcconfig` (not committed), then bootstrap again.

```
DEVELOPMENT_TEAM = ABCDE12345
```

**On a simulator, without opening Xcode:**

```sh
Scripts/run.sh <simulator-udid>     # builds, signs ad hoc, installs
```

**Without a server:** launch with `-ShelfDemo YES` (debug builds only) for a demo library. `-ShelfSearchProgress 0.5` holds search's pull halfway, for pictures of it.

### Tests

Swift Testing, in `ShelfTests/`:

```sh
xcodebuild test -project Shelf.xcodeproj -scheme Shelf \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData
```

They cover the API client against recorded responses (`fixtures/api/`), sync, the local data store, reply parsing (`fixtures/replies/`, shared with ij5.dev), the prompts, the Home Screen layout and its rules ([design/audit-0.1.md](design/audit-0.1.md)), the UIKit Home Screen (`HomeViewTests`: the icon outline against Springboard's, drops, page flips, the menu, the jiggle), search (`SearchTests`: sections, the index, Return, the list's rows, the warp's spring), the motion curves, and the feature apps in `fixtures/apps/`.

## The server

The server half is in the ij5.dev repo, on the branch `shelf-apps`. It adds:

- migrations `0009`–`0011`;
- `/api/apps`, `/api/apps/{slug}/data` and `/api/install-keys`;
- admin pages for apps.

It isn't deployed yet.

```sh
npm run db:migrate          # applies the migrations to the remote D1
npm run deploy
```

To run it on this Mac and point a simulator at it:

```sh
npm run db:migrate:local
npm run dev -- --port 8787 --strictPort
```

Then connect Shelf to `http://localhost:8787` with the token whose hash is `AUTH_HASH` in `.dev.vars`.

## Code

```
Shelf/
  Home/       the Home Screen in UIKit: the icon renderer, pages, dock, long press and menu, drag, edit mode, search (App Library's list), wallpaper, the stage that owns it all
  Runner/     running an app: the card, its open and close motion, error screen, source rewriting
  Motion/     springs, and layer animation that starts from the presentation layer
  Create/     New App and Change…: prompts, reply parsing, preview, install keys
  Store/      API client, source cache, sync, settings, Keychain
  Data/       app data: the DB store, its sync, and the db:// protocol apps reach it through
  Model/      AppMeta, layout, tints, JSON values
  Settings/   Settings and the first-run connect screen
  Resources/  prompts and the app icon
ShelfTests/   unit tests
fixtures/     API responses, reply-parser cases, one feature app per prompt section
Vendor/       the Kiln patch; Kiln itself is fetched by the bootstrap and not committed
design/       Springboard reference measurements and notes
```

## Design notes

Decisions that aren't obvious from the code:

- **Measured from Springboard.** The Home Screen's numbers come from screenshots of the real one on an iPhone 17 ([design/reference/](design/reference/)): 64 pt icons, a dock inset 17 pt on every side, a 26% icon corner (the rounder outline of iOS 26 and 27), the minus badge, and the long-press lift and menu. The dock, the search pill, the search field and the edit-mode buttons share one definition of clear system glass (`HomeGlass`), never a hand-made blur.
- **The Home Screen is UIKit and Core Animation.** Everything the stage shows is UIKit; only the sheets, the error screen and the app inside a card are SwiftUI. The stage reads `HomeModel` and `LibraryStore` in `updateProperties()` and `layoutSubviews()`, which UIKit tracks for observation. Each icon is a sibling at an exact point, so a reorder is points changing on additive `UIView` springs, and a card opens from, and lands on, exactly where its icon is.
- **One icon renderer.** `IconArtView` draws every icon in Core Animation: the grid, the dock, a card's face, search's rows, and the previews in sheets. Its outline is a path, not a layer's `cornerRadius`: Core Animation's continuous corner is up to 6 pixels rounder at 3x than Springboard's, and SwiftUI's continuous rounded rectangle matches Springboard's to the pixel. Light or dark icons come from one trait, `IconToneTrait`, set on the window.
- **The jiggle costs the main thread nothing.** Each icon's wobble is one repeating Core Animation animation that the render server plays by itself, each starting at its own moment. The icon is rasterized while it jiggles or pages, so its rim's mask and its label's shadow aren't drawn again every frame. Animations ask for 120 Hz, which an iPhone app only gets with `CADisableMinimumFrameDurationOnPhone` in Info.plist.
- **Apps are cards Shelf drives in UIKit.** A SwiftUI `fullScreenCover` with a zoom transition closed like a sheet. Instead, `HomeStage` owns the layers. A card follows the finger over the live Home Screen and springs into its icon with the gesture's velocity. Every animation starts from the presentation layer, so a card can be caught mid-flight. The system's edge gestures are deferred only while an app is open.
- **Search is App Library's, with its bar at the bottom.** The pill is one piece of glass that stretches into App Library's field as you pull down (or tap), carrying one label (drawn at the field's size, scaled down to the pill's), and rides up with the keyboard. The whole pull is one number on a spring that a display link steps (`ValueSpring`): the glass, the label, the ✕, the Home Screen blurring and fading, the backdrop and the list are all set from it in the same frame, so nothing is ever shown twice, and a finger catches it exactly where it is. The list is a `UICollectionView` list: a section per letter, a cloud on apps not downloaded yet, and an A–Z # index of Shelf's own (the collection view's can't be coloured or sized). A row opens its app from its icon, the card closes back into it, and then search closes. Every number is measured from App Library ([design/reference/](design/reference/), "Search").
- **One private API, in one file.** Search's backdrop is a `CABackdropLayer` with Core Animation's own `gaussianBlur` and `colorMatrix` filters (`Shelf/Home/PrivateBackdrop.swift`), because App Library's blur is a measured 40 pt Gaussian that has to follow the finger, and `UIBlurEffect` has a fixed radius and tint per style. Without those classes it falls back to a plain dim.
- **Settings is an icon like any other.** It sits in the layout under `:settings`, which no slug can be, so it moves to any page or within the four-place dock and search finds it. It can't be deleted, its menu has only Edit Home Screen, and a tap opens the Settings sheet.
- **Pages don't shift under a drag.** A page that a drag empties stays until Done, as on Springboard. Done drops it, and the page in view follows its icons.
- **A long press is Springboard's.** Touch-down darkens the icon. Held still, it lifts and its menu opens beside it while everything else dims. Moving on closes the menu, starts edit mode and carries the icon. In edit mode a short hold picks an icon up, and a quicker swipe turns the page. The menu is Shelf's own glass panel: once `UIContextMenuInteraction`'s menu is up, UIKit cancels the touch for every other recognizer, the window's included, so the finger could never carry on into a drag. Edit mode also starts from a long press on the wallpaper.
- **Icons are light or dark.** Dark icons are near-black tiles with the glyph in the app's colour, as Springboard's are. Clear isn't drawn any more; Settings still offers it until Icon Appearance replaces the setting (PLAN.md §0.5).
- **Apps can't overwrite each other's settings.** Kiln puts `@AppStorage` in the shared `UserDefaults.standard`, so Shelf rewrites each key to `<slug>.<key>` before running an app. It's not a security boundary, so Shelf keeps nothing of its own there.
- **`DB` is plain networking.** Kiln can already make requests, so Shelf appends a small `DB` helper to apps that use it. The helper talks to a `db://` URL scheme that Shelf answers on the phone from a local store, which syncs with ij5.dev. The key travels in a `DB-Key` header, because a key in the URL would be cut at `?` or `#`.
- **Kiln is patched.** 0.2.1 couldn't write JSON: `JSONEncoder().encode` was missing, `[Todo].self` threw, and a decoded `UUID` came back as a `String`. `Vendor/kiln-0.2.1.patch` fixes all three. The rebuild in PLAN.md replaces it.
- **Deleting an app deletes everything, everywhere.** Delete App sends `DELETE /api/apps/{slug}?data=delete`, which drops the app, every version Revert could reach, its data and its unused install keys (a live update key would otherwise make the app again). On the phone, `AppCleanup` is the one list of what an app leaves behind (source, `DB` store with its pending writes, `@AppStorage`, launch snapshot), and a sync that finds an app gone runs the same list, so other phones follow. The icon goes at once, but the phone's copy only once the server answers, so a refusal brings the icon back with nothing lost. Offline, the copy goes at once and the deletion waits in `deletions.json` for the next sync, which sends it before listing apps.
- **The server keeps history.** `POST /api/apps/{slug}/revert` backs the Revert menu item. `rev` comes from a counter table, not `MAX(rev) + 1`, which could go backwards after a purge. A closed sheet's unused install key is reused while it has ten minutes left, since the server allows twenty live keys.

## Not done yet

- A 120 fps check in Instruments on an iPhone. On the simulator, Time Profiler takes no samples from Shelf in 4 s of jiggling with a full page: nothing runs on the main thread. A frame-by-frame comparison of a finger-driven close with Springboard's is also still to do. The simulator can't perform the system's home gesture, so there's nothing to compare against.
- Picking up more than one icon at once (tapping others mid-drag, as on Springboard).
- With an app's own keyboard up, the swipe from the bottom edge lands on the keyboard and can't close the app. The drag down from the status bar still works.
- A device token in place of the admin token on the phone, minted like install keys and limited to apps, data and keys.
- Live updates to an app's data while it's open, so a change from another device shows without reopening.
- Data shared between apps.
- Home Screen shortcuts and Spotlight entries for apps, through App Intents.

## Credits

Kiln is by [@jc_builds](https://twitter.com/jc_builds) at [Haplo](https://haploapp.com), MIT-licensed.
