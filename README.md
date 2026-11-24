# Shelf

An iPhone Home Screen for apps you make yourself.

Every app on Shelf is a single SwiftUI file that a model wrote for you. The files live on [ij5.dev](https://ij5.dev). Shelf syncs them to the phone, shows them as icons on a Springboard-style Home Screen, and runs them on the device with Kiln, an interpreter for Swift. Kiln began as [haplollc/Kiln](https://github.com/haplollc/Kiln); Shelf keeps its own copy in [Packages/Kiln/](Packages/Kiln/) and is rebuilding it there. There's no compiler, no Xcode project per app, and no App Store. Describe an app, and a minute later it's an icon you can tap.

Shelf needs iOS 27.

## How it works

1. **Make.** Tap **New App** (top left in edit mode, or on an empty Home Screen), describe the app, and copy the prompt Shelf writes into any chat model or coding agent. The prompt tells the model exactly what Kiln can run.
2. **Install.** Either the agent installs the app itself, with a one-time key in the prompt (`PUT /api/apps/<slug>`), or you paste the model's reply back into Shelf, try it in a live preview, and tap Install. Before Install, Shelf checks the reply with `Kiln.check` and `Kiln.validate`: an API Kiln doesn't have, wrong labels, an `await` where nothing can wait, or an action that fails is shown in the preview's place with its line, and Install stays off until it's fixed; what Kiln accepts but doesn't do yet is listed and doesn't block. A reply that can't be installed becomes the sheet: its error screen, with **Copy for Agents**, which sends it back to the agent with the sheet's key to fix and install ([light](design/shots/new-app-check-light.jpg), [dark](design/shots/new-app-check-dark.jpg)).
3. **Sync.** Shelf keeps a copy of every app's source on the phone, so the library works offline, and syncs with ij5.dev on launch, on returning to Shelf when the last sync is stale, and from **Sync Now** in Settings.
4. **Run.** Tapping an icon runs the source through Kiln. The app opens as a card that grows out of its icon, and closes with a swipe up from the bottom edge or a drag down from the status bar.
5. **Keep data.** Apps save through `DB`, a small key-value store Shelf provides. It works offline and syncs to your other devices through ij5.dev. `@AppStorage` is for preferences that wouldn't matter if lost.

**Changing an app:** long-press its icon for **Change…** (the same flow, with the current source in the prompt), **Reload App**, **Copy Source**, and **Revert** to the version before the last change. **Delete App**, there or from the minus badge in edit mode, deletes the app and its data on every device.

**What an app can use:** the list is the prompt itself. Its "What works" and "What doesn't work" are built from Kiln's [kiln-manifest.json](Packages/Kiln/kiln-manifest.json), which Shelf bundles (`Shelf/Create/PromptCatalog.swift`): one line per family with what it has and the notes on what works only in part, then the families not in Kiln yet, what's accepted but does nothing, the Swift Kiln's probes find failing, and the won't-do list. The rest is written by hand in [Shelf/Resources/Prompts/new.md](Shelf/Resources/Prompts/new.md). Every family the prompt lists has an app in [fixtures/apps/](fixtures/apps/) that names it in its `// Covers:` line and has to run and draw, so the list stays true.

## What's next

[PLAN.md](PLAN.md) starts with Shelf itself: an audit of how the Home Screen behaves, moving the Home Screen to UIKit and Core Animation (the sheets stay SwiftUI), search rebuilt as App Library's list, deleting apps, Automatic/Light/Dark icons in place of Clear, the dock's shape, a card that stays on screen during a swipe up, and a better launch screen, all done but building an app off the main thread, which waits for the rewrite. Then it rebuilds Kiln, which is now in this repo and down to one engine:

- **The rebuild:** real `async` (built: code that waits runs on resumable frames on the heap), a registry of bridges that also drives the prompt and a coverage report, then a bytecode VM.
- **Then, in rounds:**
  - the rest of SwiftUI;
  - haptics, sharing, text parsing, units, audio, `WebView`, `Chart3D` and WebSockets;
  - files, photos, the camera, motion and location;
  - Vision and Foundation Models;
  - widgets on Shelf's Home Screen, written with WidgetKit's API.

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./Scripts/bootstrap.sh     # generates Shelf.xcodeproj
open Shelf.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't committed. Change `project.yml`, not the project, and run the bootstrap again. Kiln is a local Swift package in `Packages/Kiln`, so nothing is fetched.

**On a phone:** put your team in `Config/Local.xcconfig` (not committed), then bootstrap again.

```
DEVELOPMENT_TEAM = ABCDE12345
```

**On a simulator, without opening Xcode:**

```sh
Scripts/run.sh <simulator-udid>     # builds, signs ad hoc, installs
```

**Without a server:** launch with `-ShelfDemo YES` (debug builds only) for a demo library. `-ShelfSearchProgress 0.5` holds search's pull halfway, for pictures of it. `-ShelfDemoDeleteFails YES` makes the demo's server refuse every Delete App a second later, so the icon comes back. `-ShelfDebugAskPermission location` (or a list, `camera,microphone`) asks for it once the Home Screen is up, as the app `-ShelfDebugAskPermissionApp workout` (the library's first by default): Shelf's sheet, then iOS's prompt, then Settings › Permissions. `xcrun simctl privacy <udid> revoke|reset …` fakes what iOS has said for Shelf. `-ShelfDebugReply <Swift file on the Mac>` opens New App with that file pasted as the reply, for its preview and error screen (the sheet has no Paste button); `-ShelfDemoFixtures <folder>` gives one icon per Swift file there, broken ones included.

### Tests

Swift Testing, in `ShelfTests/`:

```sh
xcodebuild test -project Shelf.xcodeproj -scheme Shelf \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData
```

They cover the API client against recorded responses (`fixtures/api/`), sync, the local data store, reply parsing (`fixtures/replies/`, shared with ij5.dev), the prompts, the Home Screen layout and its rules ([design/audit-0.1.md](design/audit-0.1.md)), the UIKit Home Screen (`HomeViewTests`: the icon outline against Springboard's, drops, page flips, the menu, the jiggle), search (`SearchTests`: sections, the index, Return, the list's rows, the warp's spring), Delete App (`DeleteAppUITests`: the menu, the badge, the alert, the icon leaving and coming back), permissions (`PermissionTests`: the ledger's file, every answer's change, iOS refusing Shelf, the ask flow with faked answers, cleanup, the New App preview), the motion curves, and the feature apps in `fixtures/apps/`.

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
  Permissions/  what each app may use: capabilities, the ledger of answers, the gate, Shelf's sheet, iOS's side
  Settings/   Settings (with Permissions) and the first-run connect screen
  Resources/  prompts and the app icon
ShelfTests/   unit tests
fixtures/     API responses, reply-parser cases, one feature app per prompt section
Packages/Kiln/  Kiln, the interpreter apps run on: forked from upstream 0.2.1, with its own tests, Kiln Lab, and benchmarks
design/       Springboard reference measurements and notes
```

## Design notes

Decisions that aren't obvious from the code:

- **Measured from Springboard.** The Home Screen's numbers come from screenshots of the real one on an iPhone 17 ([design/reference/](design/reference/)): 64 pt icons, a dock inset 17 pt on every side with a 38.75 pt continuous corner (fitted row by row; not the display's radius less the inset, which is 25 px rounder at 3x), a 26% icon corner (the rounder outline of iOS 26 and 27), the minus badge, and the long-press lift and menu. The dock, the search pill, the search field and the edit-mode buttons share one definition of clear system glass (`HomeGlass`), never a hand-made blur.
- **The Home Screen is UIKit and Core Animation.** Everything the stage shows is UIKit; only the sheets, the error screen and the app inside a card are SwiftUI. The stage reads `HomeModel` and `LibraryStore` in `updateProperties()` and `layoutSubviews()`, which UIKit tracks for observation. Each icon is a sibling at an exact point, so a reorder is points changing on additive `UIView` springs, and a card opens from, and lands on, exactly where its icon is.
- **One icon renderer.** `IconArtView` draws every icon in Core Animation: the grid, the dock, a card's face, search's rows, and the previews in sheets. Its outline is a path, not a layer's `cornerRadius`: Core Animation's continuous corner is up to 6 pixels rounder at 3x than Springboard's, and SwiftUI's continuous rounded rectangle matches Springboard's to the pixel. Light or dark icons come from one trait, `IconToneTrait`, set on the window.
- **The jiggle costs the main thread nothing.** Each icon's wobble is one repeating Core Animation animation that the render server plays by itself, each starting at its own moment. The icon is rasterized while it jiggles or pages, so its rim's mask and its label's shadow aren't drawn again every frame. Animations ask for 120 Hz, which an iPhone app only gets with `CADisableMinimumFrameDurationOnPhone` in Info.plist.
- **Apps are cards Shelf drives in UIKit.** A SwiftUI `fullScreenCover` with a zoom transition closed like a sheet. Instead, `HomeStage` owns the layers. A card follows the finger over the live Home Screen, and the system's edge gestures are deferred only while an app is open.
- **A card closes as Springboard's does, measured from an iPhone 17** ([design/reference/springboard/](design/reference/springboard/README.md), the real-device swipe-up). Under the finger it shrinks around the point the finger holds, and its top edge is rubber-banded short of the screen's top, so a long swipe never carries it off the screen. The release is decided by the finger's travel and speed, but the springs start at the card's own speed, so a flick never throws it. Once let go it flies on a spring per property (`CardFlight`: centre, width, height, each fitted to Springboard's frames), so it shrinks almost in place, turns from portrait to square, and glides onto its icon. On the way the picture and the glyph keep their shape and are drawn at the card's width from its top (only the tile's fill stretches), its corners stay the display's until it is nearly an icon, it leans in depth by where its icon is, and the Home Screen behind comes into focus as it lands. The card has no Core Animation animations: every frame places it, in one transaction, so a finger catches it exactly where it is, and it heads for wherever its icon is that frame, so the pages can be turned under a landing card. It lands where the icon will be once the Home Screen has grown back, not where its scaled-down picture is.
- **An app opens on its launch surface, as Springboard's do** (measured from the same iPhone 17's opens). The card's face crosses from the icon to the surface within the first half of its growth, the Home Screen blurs late and dims as it grows, and the card leans away from its icon. The surface is the app's last snapshot when one is fresh, else a plain one shaped like its first screen. A snapshot is taken with `drawHierarchy` as the card closes and kept in `Caches/Snapshots/<slug>/`; its file name holds what makes it fresh (the source's revision, light or dark, the text size), so finding one is a look in the folder. Without one, `LaunchLayout` reads the root view's `body` as text: a `List` or `Form` sits on the grouped background, a navigation container gets an empty bar. No glyph and no tint: a saturated slab cut to a white app reads as nothing iOS does. The face stays under the app until the built app (or the error screen) has crossfaded in over it, as one picture. Every frame of the growth is seen: the card's flights run on a clock of their own (`CardClock`) that starts on its icon and never moves on by more than two frames, so the 50–90 ms a cold open spends building the card costs that time instead of skipping the icon growing. The card is one composited picture: its outline, the icon's face, the surface and a snapshot fading in over it are placed in one transaction, under one mask, so the picture is always exactly the card. The snapshot is read from disk while the finger is still on the icon, and so is the app's source parsed, off the main thread (`Prebuilds`), while its data's pull from the server starts: by the time the card comes to rest, what's left of building takes a millisecond or two, and the app is drawn in the next frame. Kiln and SwiftUI are warmed once, offscreen, just after launch, so the first app opened is as quick as the rest (press to the app's first frame on the simulator: 959 ms cold before, 675 ms now; about 625 ms warm, which is the card's own motion).
- **Search is App Library's, with its bar at the bottom.** The pill is one piece of glass that stretches into App Library's field as you pull down (or tap), carrying one label (drawn at the field's size, scaled down to the pill's), and rides up with the keyboard. The whole pull is one number on a spring that a display link steps (`ValueSpring`): the glass, the label, the ✕, the Home Screen blurring and fading, the backdrop and the list are all set from it in the same frame, so nothing is ever shown twice, and a finger catches it exactly where it is. The list is a `UICollectionView` list: a section per letter, a cloud on apps not downloaded yet, and an A–Z # index of Shelf's own (the collection view's can't be coloured or sized). A row opens its app from its icon, the card closes back into it, and then search closes. Every number is measured from App Library ([design/reference/](design/reference/), "Search").
- **One private API, in one file.** Search's backdrop, and the Home Screen behind an app's card, are a `CABackdropLayer` with Core Animation's own `gaussianBlur` and `colorMatrix` filters (`Shelf/Home/PrivateBackdrop.swift`): App Library's blur is a measured 40 pt Gaussian that has to follow the finger, and Springboard's behind a card is a 20 pt one whose radius shrinks as the card lands; `UIBlurEffect` has a fixed radius and tint per style and can only fade. Without those classes it falls back to a plain dim.
- **Settings is an icon like any other.** It sits in the layout under `:settings`, which no slug can be, so it moves to any page or within the four-place dock and search finds it. It can't be deleted, its menu has only Edit Home Screen, and a tap opens the Settings sheet.
- **Pages don't shift under a drag.** A page that a drag empties stays until Done, as on Springboard. Done drops it, and the page in view follows its icons.
- **A long press is Springboard's.** Touch-down darkens the icon. Held still, it lifts and its menu opens beside it while everything else dims. Moving on closes the menu, starts edit mode and carries the icon. In edit mode a short hold picks an icon up, and a quicker swipe turns the page. The menu is Shelf's own glass panel: once `UIContextMenuInteraction`'s menu is up, UIKit cancels the touch for every other recognizer, the window's included, so the finger could never carry on into a drag. Edit mode also starts from a long press on the wallpaper.
- **Icons are light or dark, and Icon Appearance says which.** Dark icons are near-black tiles with the glyph in the app's colour, as Springboard's are. Settings offers Automatic, which follows the system, and Light and Dark, which hold the icons there whatever the system does, as Springboard's Customize panel does; there's no Clear. The stage resolves the setting in one place (`StageController.holdAppearance`) and sets the result on the window as `IconToneTrait`, which every icon reads: the grid, the dock, search's rows, the lifted and carried icon, a card's face and the sheets' icons (sheets also get it in SwiftUI's environment, since a sheet keeps the value it was presented with). Labels, the glass and the wallpaper follow the system.
- **Each run of an app has a context of its own** (PLAN.md §1.7, `Shelf/Runner/AppRun.swift`). Kiln runs the app with its own `UserDefaults` suite (`shelf.app.<slug>`), which its `@AppStorage` and `UserDefaults.standard` both resolve to, so no app can reach another's settings or Shelf's; values kept before this, as `kiln.app.<slug>.<key>` in Shelf's own defaults, move into the suite the first time the app opens. It has its own folder, `Application Support/files/<slug>/`, laid out as an app container, which `URL.documentsDirectory`, `FileManager` and file reads and writes resolve into; a path that leaves it is an error. Its `DB` session, its permission gate (§4.0) and its error channel come with it. When its card lands, the run is torn down: Kiln cancels its tasks and timers, stops whatever its bridges started, and a permission sheet still up for it goes. Part of an app that fails while it runs (a `body`, a row, a style) shows Shelf's error screen in the app's place, as an app Kiln can't start does: Kiln draws every such error through the run's `KilnErrorScreen`, which Shelf provides.
- **One error screen, and a way out of it.** An app that couldn't open, one that stopped while it ran, and a reply that can't be installed all show the same screen (`ErrorScreen`): the app's icon with a warning badge, what happened, Kiln's message, and the code around the failing line, wrapped as an editor wraps it (each line under its own start, broken after a `(` or a member's `.`, never hyphenated), the line marked by its red number ([stopped](design/shots/error-stopped-light.jpg), [dark](design/shots/error-stopped-dark.jpg); [couldn't open](design/shots/error-cant-open-light.jpg), [dark](design/shots/error-cant-open-dark.jpg)). Its one button, **Copy for Agents**, copies a prompt a coding agent can fix the app with on its own: for an installed app, the Change prompt with the error as the change, the whole source and, online, a fresh update key from `KeyRing` so the agent can `PUT` the fix; for a reply, the error, the reply and the sheet's own key. Offline, or with no key, the prompt asks for the fixed file instead. `KeyRing` asks the server before handing out a key it holds, so a key an agent has used since is never handed out again.
- **`DB` is a Kiln host bridge.** `DB.load`, `DB.save` and `DB.remove` are native and synchronous, answered from the run's own session (`DBBridge`), which `AppData` saves and syncs with ij5.dev in the background. A write the server would refuse (a bad key, over 64 KB, the store full, not JSON) is an error with the app's line instead of being lost. Settings › App Data lists each app's data and files.
- **Kiln lives here.** It was a pinned upstream tag plus a patch; now it's `Packages/Kiln`, a local package whose module is still `Kiln`. The first two commits that brought it in are upstream 0.2.1 untouched, then the patch Shelf needed (0.2.1 couldn't write JSON: `JSONEncoder().encode` was missing, `[Todo].self` threw, and a decoded `UUID` came back as a `String`), so it can be offered back. Changes to Kiln are timed against 0.2.1 with `Packages/Kiln/Benchmarks/run.sh` ([Benchmarks/](Packages/Kiln/Benchmarks/README.md)); more than 10% slower on any app blocks a merge.
- **Deleting an app deletes everything, everywhere.** Delete App sends `DELETE /api/apps/{slug}?data=delete`, which drops the app, every version Revert could reach, its data and its unused install keys (a live update key would otherwise make the app again). On the phone, `AppCleanup` is the one list of what an app leaves behind (source, settings suite, files folder, `DB` store with its pending writes, launch snapshot, permission grants), and a sync that finds an app gone runs the same list, so other phones follow. The icon goes at once, but the phone's copy only once the server answers, so a refusal brings the icon back with nothing lost. On screen it is Springboard's, measured frame by frame: the system alert ("Delete “Habits”?", Cancel and Delete), then the icon shrinks to nothing about its centre in 200 ms and the others close up 230 ms later on a spring fitted to Springboard's. An icon that comes back before it has gone turns around where it is. Offline, the copy goes at once and the deletion waits in `deletions.json` for the next sync, which sends it before listing apps.
- **Permissions are per app; iOS's are per Shelf.** iOS asks once for Shelf, so Shelf asks each app's question first, in its own sheet ("Workout wants to use your location", the app's icon, what it's for, Allow and Don't Allow), and iOS's prompt follows an Allow only if iOS hasn't asked yet ([sheet](design/shots/permissions-sheet-light.jpg), [dark](design/shots/permissions-sheet-dark.jpg), [then iOS](design/shots/permissions-system-prompt-light.jpg)). The answer goes in a ledger on the phone (`Application Support/permissions.json`), never synced: a grant is to a device, as iOS's are. iOS refusing Shelf is "denied" for every app whatever the ledger says, and an app allowed here whose capability iOS has since forgotten (Allow Once, a reset) gets iOS's prompt again without Shelf's. Settings › Permissions lists each capability's apps with a switch, and says when iOS has refused Shelf, with Open Settings ([light](design/shots/permissions-settings-light.jpg), [dark](design/shots/permissions-settings-dark.jpg)). The sheet is SwiftUI, presented from UIKit over whatever is in front, because the gate is asked from inside a card or the New App sheet. A new app's preview asks as `preview:<uuid>`, which no slug can be, so it never answers for an installed app; Install moves its answers to the slug it's installed as, and closing the sheet forgets them. Only what iOS itself asks about is gated: not the photo picker, files or the raw motion sensors. Kiln's `validate` gets `StubAppPermissions`, which answers without UI.
- **The server keeps history.** `POST /api/apps/{slug}/revert` backs the Revert menu item. `rev` comes from a counter table, not `MAX(rev) + 1`, which could go backwards after a purge. A closed sheet's unused install key is reused while it has ten minutes left, since the server allows twenty live keys.

## Not done yet

- A 120 fps check in Instruments on an iPhone. On the simulator, Time Profiler takes no samples from Shelf in 4 s of jiggling with a full page: nothing runs on the main thread. A frame-by-frame comparison of a finger-driven close with Springboard's is also still to do. The simulator can't perform the system's home gesture, so there's nothing to compare against.
- Picking up more than one icon at once (tapping others mid-drag, as on Springboard).
- The card's limit and resistance at the top of a long swipe up are inferred, not measured: the real-device recording has only flicks, whose top edge never rises. The reference README says how to record the slow, long swipe that would measure them. The lean is fitted to a few recordings: the lean toward an icon above or below to two Developer closes and one open, the sideways turn to one Photos close.
- Building the app before the card comes to rest, off the main thread (PLAN.md §0.8, item 5), which waits for Kiln's rewrite. Until then an app shows its launch surface for its build time after the open.
- Launch snapshots aren't checked on a device: how long `drawHierarchy` takes at the start of a close there, and whether reading one back from disk, started on touch-down, arrives before the icon has gone (on the simulator it does; a late one fades in inside the card).
- With an app's own keyboard up, the swipe from the bottom edge lands on the keyboard and can't close the app. The drag down from the status bar still works.
- A device token in place of the admin token on the phone, minted like install keys and limited to apps, data and keys.
- Live updates to an app's data while it's open, so a change from another device shows without reopening.
- Data shared between apps.
- Home Screen shortcuts and Spotlight entries for apps, through App Intents.

## Credits

Kiln is by [@jc_builds](https://twitter.com/jc_builds) at [Haplo](https://haploapp.com): [haplollc/Kiln](https://github.com/haplollc/Kiln), MIT-licensed. Shelf's copy in `Packages/Kiln` started from its 0.2.1 release and keeps its [LICENSE](Packages/Kiln/LICENSE).
