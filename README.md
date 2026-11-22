# Shelf

A Springboard-style iPhone Home Screen for personal SwiftUI apps stored on ij5.dev and run on device with [Kiln](https://github.com/haplollc/Kiln).

The plan is [PLAN.md](PLAN.md). This file is how to build it, and where what was built differs from the plan.

## Build

Needs Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Shelf targets iOS 27.

```sh
./Scripts/bootstrap.sh        # fetches Kiln 0.2.1, applies Vendor/kiln-0.2.1.patch, generates Shelf.xcodeproj
open Shelf.xcodeproj
```

To run on a phone, put your team in `Config/Local.xcconfig` (not committed) and run the bootstrap again. The project is generated, so a team picked in Xcode would not stick.

```
DEVELOPMENT_TEAM = ABCDE12345
```

For a simulator, without opening Xcode:

```sh
Scripts/run.sh <simulator-udid>     # builds, signs ad hoc, installs
```

Tests (Swift Testing):

```sh
xcodebuild test -project Shelf.xcodeproj -scheme Shelf \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData
```

Launching with `-ShelfDemo YES` shows a library with no server behind it (debug builds only).

## Server

The server half lives in the ij5.dev repo, on the branch `shelf-apps`: migrations `0009`–`0011`, `/api/apps`, `/api/apps/{slug}/data`, `/api/install-keys`, and the admin pages. It is not deployed. To deploy it:

```sh
npm run db:migrate            # applies the three migrations to the remote D1
npm run deploy
```

To run it on this Mac instead, and point a simulator at it:

```sh
npm run db:migrate:local
npm run dev -- --port 8787 --strictPort
```

Then connect Shelf to `http://localhost:8787` with the token whose hash is `AUTH_HASH` in `.dev.vars`.

## Where the build differs from the plan

**Kiln needed a patch.** The plan's first gate (§8.4) failed: Kiln 0.2.1 has no `JSONEncoder().encode`, `[Todo].self` throws, and a decoded `var id = UUID()` comes back as a `String`. Apps could not have saved anything through `DB`. `Vendor/kiln-0.2.1.patch` adds the three, with a test, and `Scripts/bootstrap.sh` applies it to the pinned tag. It is written to go upstream; once a Kiln release has it, delete the patch and pin the package in `project.yml`.

**The prompts were corrected against what Kiln really runs.** `Shelf/Resources/Prompts/` is the source of truth now, not the plan's appendix. `fixtures/apps/` holds an app per section of "What works", and each must run and draw. That moved `ShareLink`, `Canvas`, `@FocusState`, `.sensoryFeedback` and gestures out of "What works" and added a few warnings.

**The Home Screen is measured from Springboard, not the plan's starting values.** The numbers were read out of screenshots of the real Home Screen on an iPhone 17 (`design/reference/`): 64 pt icons rather than 60, a dock inset 17 pt on every side rather than 12 and 8, and an icon corner of 26% rather than 22.37%, which is the rounder outline iOS 26 and 27 draw. The dock, the search pill and the search field are one definition of clear system glass, which is what measures the same as Springboard's dock over the same backdrop.

**Apps open and close as cards Shelf drives, in UIKit.** The plan's `fullScreenCover` with a zoom transition closed like a sheet sliding over a grey scrim. Now `HomeStage` owns the Home Screen's layers and an app is a card that follows the finger over the live Home Screen and springs into its icon with the gesture's velocity. Every retargeted animation starts from the presentation layer, so a card can be caught mid-flight. An app closes with a swipe up from the bottom edge or a drag down from the status bar; Shelf defers the system's own edge gestures only while an app is open.

**Search sits above the keyboard, and the pill becomes it.** The plan moved the field to the top of the screen, which left nothing to morph. The pill is one piece of glass that stretches into the field as the finger pulls down, or on a tap, and rides up with the keyboard, as on iOS 27.

**A long press means one thing at a time.** It opens the icon's menu on a still Home Screen and starts a drag once icons jiggle. Offered together, the menu's lifted preview swallows the drag and no drop target hears about it. So dragging an icon no longer enters edit mode by itself; the menu's Edit Home Screen and a long press on the wallpaper do.

**Icon styles are Color and Clear.** Color draws dark tiles in dark mode, as Springboard does. The plan's separate Default, Dark and Tinted choices are gone.

**Smaller changes**

- The default wallpaper is a photo; the mesh gradient is the second choice in Settings.
- Sync Now is in Settings only. The wallpaper has no context menu, because a long press there enters edit mode.
- `AppMeta` has a `revertible` flag and the server has `POST /api/apps/{slug}/revert`, which is what the icon menu's Revert calls.
- A closed sheet's unused install key is reused by the next sheet while it has ten minutes left, since the server allows twenty live keys.
- On the server, `rev` comes from a counter table rather than `MAX(rev) + 1`, which could go backwards after a purge.

**Not done**

- The 120 fps check in Instruments (§13.1) and a frame-by-frame comparison of a finger-driven close against Springboard's: the simulator can't be made to perform the system's home gesture, so there is no recording to compare with.
- With an app's own keyboard up, the swipe from the bottom edge lands on the keyboard and can't close the app. The drag from the status bar still does.
- A `DB` key containing `?` or `#` is cut short at that character, because the helper puts the key in a URL as it is.
- Everything under "Later" in the plan.

## Layout

```
Shelf/          the app: Model, Store (API, cache, sync), Data (app data, db:// protocol),
                Home (the stage, icons, dock, search), Runner (app cards, the rewriter),
                Motion (springs and layer animation), Create (prompts, paste, preview), Settings
ShelfTests/     unit tests
fixtures/       API responses, reply-parser cases (shared with ij5.dev), feature apps
Vendor/         the Kiln patch; Kiln itself is fetched here by bootstrap and not committed
design/         the Springboard reference and Shelf's screenshots
```
