# Shelf — plan

An iPhone Home Screen for personal apps. Each app is a single Swift file stored on ij5.dev and run on device by [Kiln](https://github.com/haplollc/Kiln). Shelf should feel like Springboard: icons on a wallpaper, a glass dock, apps that zoom out of their icon and back into it.

Two repos change:

- **ij5.dev**: adds an apps table, an API and an admin editor. None of this exists yet.
- **shelf**: adds the iOS app.

---

## 0. What the research changed

| Finding | Source | Consequence |
|---|---|---|
| Kiln stores `@AppStorage` in `UserDefaults.standard` under `kiln.app.<key>`, which every app shares. | `Engine/KERenderer.swift` | Two apps that both use `@AppStorage("count")` would overwrite each other. Shelf rewrites each key to `<slug>.<key>` before running the app (§6.3). |
| Compile errors come back as `"Line N: message"` in `KilnResult.errors`. Errors inside a running body appear as Kiln's own red label and never reach the host. | `Engine/KEEngine.swift:62`, `KErrorView` | Shelf calls `Kiln.run` directly instead of `KilnView`, so it can show its own error screen with the failing line (§7). Render-time errors stay Kiln's to show. |
| `Kiln.run` is `@MainActor` and synchronous. `await URLSession…` inside an app blocks for up to 20 s. | README, Limitations | Shelf runs the app once per open and keeps the result in `@State`. App authors should use `dataTask` for network calls. |
| `Kiln.validate` fires every action once, side effects included. | `Kiln.swift` | Shelf never validates on device. Validation goes on the Later list. |
| The latest tag is `0.2.1`. | `git ls-remote` | Pin the package with `.upToNextMinor(from: "0.2.1")`. Before 1.0, a minor release can break the API. |
| On iOS 26, interactive dismiss of `.navigationTransition(.zoom)` with `fullScreenCover` has open bugs: the source icon disappears and frames are misaligned. | Apple Developer Forums [796279](https://developer.apple.com/forums/thread/796279), [807208](https://developer.apple.com/forums/thread/807208), [807715](https://developer.apple.com/forums/thread/807715) | Use the zoom transition, but keep a known-good fallback behind one flag (§6.1). |
| No public source documents the iOS 26 or 27 Home Screen metrics in points. | Searches | Treat the metrics in §5 as starting values, and tune them by overlaying Shelf screenshots on real Springboard screenshots (§9). |
| No server API exists. | `ij5.dev/src/routes/api` | Build it with the conventions the links API already uses (§1). |

**Deployment target: iOS 26.** It brings `glassEffect` and `MeshGradient`, which the Springboard look depends on. iOS 27 is current, Kiln itself needs iOS 17, and Shelf is a personal app, so dropping older versions costs nothing.

---

## 1. Server (ij5.dev)

### 1.1 Migration `migrations/0009_apps.sql`

```sql
CREATE TABLE apps (
  slug       TEXT PRIMARY KEY,         -- SLUG_PATTERN
  name       TEXT NOT NULL,            -- label under the icon, ≤ 32 chars
  icon       TEXT,                     -- SF Symbol name; null → "app"
  tint       TEXT NOT NULL,            -- one of TINTS (see 1.2)
  source     TEXT NOT NULL,            -- ≤ 256 KB
  version    TEXT NOT NULL,            -- sha256(source + name + icon + tint), base64url, 16 chars
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

`version` is a hash of the app's content, not a counter. Saving the same content twice leaves it unchanged, so the phone downloads nothing, and two edits racing each other can never produce the same version for different content. Name, icon and tint are part of the hash, so renaming an app also reaches the phone.

Apps live only under `/api/apps`. They take no root slug, and nothing in `RESERVED` needs to change.

### 1.2 `src/lib/server/apps.ts`

This file holds `listApps` (metadata only, so `source` is never read for the index), `getApp`, `putApp` and `deleteApp`, in the style of `pastes.ts`.

`TINTS` is a fixed list of named colours: `red orange yellow green mint teal cyan blue indigo purple pink brown gray`. Names rather than hex codes mean the phone maps each one to the matching `Color.red` and so on. Those system colours adapt to light mode, dark mode and increased contrast; a hex code would not.

### 1.3 API, with the same `authorize`, `apiJson` and `apiError` as links

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/api/apps` | | `{ "apps": [AppMeta] }` with a strong `ETag`. `If-None-Match` gets a `304`. |
| GET | `/api/apps/{slug}` | | `AppFull` |
| PUT | `/api/apps/{slug}` | `{ name, icon?, tint, source }` | `201` if created, `200` if updated |
| DELETE | `/api/apps/{slug}` | | `{ slug, deleted: true }` |

```ts
type AppMeta = { slug: string; name: string; icon: string | null; tint: Tint; version: string; updated_at: number };
type AppFull = AppMeta & { source: string };
```

The ETag is a hash of all the versions combined. With it, the sync on every launch usually costs a single `304`.

Writes use `PUT` rather than `POST` plus `PATCH`, because an app is a whole document and uploading it again is the normal way to change it. A future CLI can then run `curl -T`.

### 1.4 Admin `/admin/apps`

- A list sorted by name, with an icon preview, the name and when it was last updated.
- An editor with name, an SF Symbol name and a live preview tile, a row of tint swatches, and a monospaced `source` textarea with a byte counter (`MAX_APP_BYTES`, shared through `$lib/types`).
- A row added to `/admin/api` for the new endpoints.

### 1.5 Tests (vitest, next to the existing ones)

- `apps.test.ts`:
  - version stability: same input gives the same hash, and any field change gives a new one
  - size limit
  - tint whitelist
  - a list query that never selects `source`
- A route test: `If-None-Match` returns `304`, and a wrong token returns `401` without echoing the token.

---

## 2. iOS project

```
Shelf/
  project.yml              XcodeGen; the .xcodeproj is generated, not committed
  Shelf/
    ShelfApp.swift
    Model/      AppMeta.swift, AppFull.swift, Tint.swift, Layout.swift
    Store/      Keychain.swift, Settings.swift, AppCache.swift, SyncEngine.swift, LibraryStore.swift
    Home/       HomeScreen.swift, IconGrid.swift, AppIcon.swift, Dock.swift, Wallpaper.swift,
                PageDots.swift, SearchPill.swift, JiggleModifier.swift, EditDropDelegate.swift
    Runner/     RunnerView.swift, SourceRewriter.swift, ErrorScreen.swift
    Settings/   SettingsView.swift
  ShelfTests/   SyncEngineTests.swift, SourceRewriterTests.swift, LayoutTests.swift
```

- The only dependency is Kiln, pinned as in §0.
- Strict concurrency is on (Swift 6 language mode).
- The UI targets portrait only, like Springboard on iPhone.

---

## 3. Connect and settings

- Stored settings:
  - the site URL in `UserDefaults`, defaulting to `https://ij5.dev`
  - the token in the Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- First run shows one screen: an app glyph, a token field and a Connect button. Connect checks the token with `GET /api/apps` before saving anything. A wrong token shakes the field and leaves no saved state.
- Settings opens as a sheet from the gear icon in the dock (§5.4). It contains:
  - Site
  - Token (masked, with Change)
  - Sync Now, with a "last synced" time
  - Wallpaper (built-in, or a photo from `PhotosPicker`)
  - Reset Layout
  - Sign Out, which clears the token, the cache and each app's storage

---

## 4. Sync

`SyncEngine` is an `actor`. `LibraryStore` is a `@MainActor @Observable` that owns what the UI shows.

**Triggers:**

- launch
- `scenePhase == .active` once 10 minutes have passed since the last sync
- Sync Now in Settings
- the wallpaper's context menu

There is no pull-to-refresh: Springboard has none, and a downward swipe on the Home Screen means search.

**Steps:**

1. `GET /api/apps` with `If-None-Match: <stored etag>`. On `304`, stop here.
2. Compare each app's version with the cache. For each app that is new or changed, `GET /api/apps/{slug}`, with at most 4 requests at a time (`withThrowingTaskGroup`).
3. Write each source atomically to `Application Support/apps/{slug}.swift` with `.atomic` and `.completeFileProtectionUntilFirstUserAuthentication`.
4. Write `index.json` last. It records, per app, the version that is on disk, which is not always the version the server listed. When one app fails to download, its old version stays in the index and the next sync retries it.
5. Only after `index.json` is written, delete `{slug}.swift` files and AppStorage keys (`kiln.app.{slug}.*`) for apps that are no longer listed.
6. If step 1 fails (offline, `5xx`, `401`), the cache is left untouched, so the apps keep working offline. A `401` marks the token as invalid, and Settings says so.

Before the first frame, `LibraryStore` reads `index.json` synchronously, so the Home Screen never flashes empty on launch.

**How sync appears on the Home Screen:**

- While an app's source downloads, its icon shows the App Store install state: the icon dimmed, with a circular progress pie in the middle.
- After an app is added or updated, a blue dot sits before its label until the app is first opened, the same as a newly installed iOS app.
- When a sync fails and the app has a cache, a glass capsule drops from the top of the screen, like a system banner: an `exclamationmark.icloud` glyph and "Offline". It disappears after 3 s or on a tap.
- A `401` uses the same banner with "Token Expired", and tapping it opens Settings.
- On the first run, when there is no cache, the error replaces the grid as a `ContentUnavailableView`.

---

## 5. Home Screen

The aim is that a screenshot of Shelf placed next to Springboard looks the same at a glance. Every number below is a starting value for the overlay check in §9.

### 5.1 Wallpaper

- The default is a `MeshGradient` with 3×3 points in deep blue and violet tones, with separate palettes for light and dark mode. The middle points drift slowly over 20 s (`TimelineView(.animation)`). Reduce Motion turns the drift off.
- An optional photo from `PhotosPicker`, scaled to fill. The `scaledToFill` and safe-area handling match how Springboard crops a wallpaper.
- The wallpaper extends under the status bar and the home indicator (`ignoresSafeArea()`).

### 5.2 Icon grid

- **Layout:** 4 columns and 6 rows per page, the iPhone default.
- **Size:** `iconSize = 60pt` for a 393pt-wide screen, scaled by `width / 393` and rounded to whole points, so Pro Max models get about 64pt the way Springboard scales.
- **Horizontal spacing:** side insets of about 27pt, with the 4 columns spaced evenly in the remaining width.
- **Rows:**
  - The top row starts about 14pt below the status bar.
  - Rows are distributed evenly in the height between the status bar and the dock, which is how Springboard does it, rather than a fixed gap.
- **Paging:**
  - More than 24 apps continue on another page in a horizontal `ScrollView` with `.scrollTargetBehavior(.paging)`.
  - Page dots replace the search pill while the user swipes, then fade back after 1 s.

### 5.3 App icon

- **Shape:** `RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)`, the continuous curve that approximates Apple's superellipse mask. A plain `cornerRadius` is not close enough.
- **Fill in light mode:** a vertical `LinearGradient` from `tint` lightened by 12% at the top to `tint` at the bottom. The SF Symbol is white, about `size * 0.5`, `.medium` weight, centred optically. `symbolRenderingMode(.hierarchical)` gives two-tone glyphs depth.
- **Fill in dark mode:** follows iOS 18+ dark icons. The fill is a near-black gradient (`#2C2C2E` → `#1C1C1E`) and the glyph takes the tint colour.
- **Edge:**
  - a 0.5pt inner stroke of white at 18% opacity, strongest on the top edge (`strokeBorder` with a top-to-bottom gradient)
  - the specular rim that Liquid Glass icons have
- **Shadow:** none. Springboard icons cast no drop shadow.
- **Label:**
  - `.system(size: 12)`, white, on one line, truncated at the tail
  - 6pt below the icon, as wide as the icon plus 14pt
  - A soft `shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)` keeps it readable on light wallpapers.
- **Pressed state:** on touch-down the icon darkens with `brightness(-0.25)`, with no scale change. Springboard darkens icons rather than shrinking them. This needs a custom `ButtonStyle` that reads `configuration.isPressed`.
- **Haptic:** `.sensoryFeedback(.impact(weight: .light), …)` when an app launches.
- **Long-press:** a `contextMenu` with Edit Home Screen, Reload App and Copy Source, and a `preview` showing the icon at 2× scale, like an app's quick-actions menu.

### 5.4 Dock

- **Contents:** up to 4 slots: the apps the user pins, plus Settings, which always stays in the dock with a gray gradient and the `gearshape.fill` glyph.
- **Container:** `GlassEffectContainer` with `.glassEffect(.regular, in: .rect(cornerRadius: 32, style: .continuous))`, inset about 12pt from the screen edges and about 8pt above the bottom safe area.
- **Corner radius:** inner radius = display corner radius − inset, so the dock is concentric with the screen corners. That concentricity is the detail that gives a fake dock away when it's wrong.
- **Labels:** dock icons show no labels, as on Springboard.

### 5.5 Search pill

- **Appearance:** a glass capsule above the dock showing a `magnifyingglass` glyph and "Search", the same as iOS 18+.
- **Opening search:** tapping the pill, or swiping down anywhere on the grid, opens search.
  - The wallpaper blurs (`.blur(radius: 30)` plus dimming).
  - A search field focuses at the top.
- **Search behaviour:**
  - Results are the app icons whose names match, in a 4-column grid; the best match comes first and opens with Return.
  - Tapping outside the field or swiping down closes search.

### 5.6 Edit mode

Edit mode does what Springboard's does that still makes sense here. Apps come from the server, so they can't be deleted on the phone.

- **Entering:**
  - Edit Home Screen in an icon's context menu.
  - A long-press on empty wallpaper.
  - Starting to drag an icon.
- **Jiggle:** each icon rotates ±1.6° and shifts ±0.6pt vertically. The period is 0.26 s with a random phase per icon, so the icons don't move in step. The animation uses `phaseAnimator`. Reduce Motion replaces it with a static grey outline.
- **Reordering:** drag-and-drop (`draggable` and `dropDestination`).
  - Other icons slide aside with `.spring(duration: 0.35, bounce: 0.15)`.
  - Holding an icon at the screen edge for 0.6 s flips to the next page.
- **Dock:** dragging an icon into or out of the dock pins or unpins it.
- **Done:** a glass capsule button in the top-right corner, plus a tap on empty wallpaper.
- **Storage:** the layout is saved locally in `layout.json` as `{ dock: [slug], pages: [[slug]] }`.
  - New apps go into the first empty slot on the last page, as on iOS.
  - Removed apps leave the layout.
  - Unknown slugs in the layout are ignored.

### 5.7 Accessibility

- **Labels:** each icon is a single `Button` with `accessibilityLabel(name)`. A "New" hint is added when the blue dot shows.
- **Dynamic Type:** labels are capped at `.xLarge`, as Springboard's are.
- **Bold Text:** label weight follows the setting.
- **Increased Contrast:** a darker label shadow and a solid dock.

---

## 6. Runner

### 6.1 Presentation

- **Presentation:** `fullScreenCover` with `.navigationTransition(.zoom(sourceID: slug, in: ns))`, and each icon (grid or dock) as `.matchedTransitionSource(id: slug, in: ns)`.
  - The app grows out of its own icon and shrinks back into it when dragged down.
  - This replaces the sheet in the original spec: a sheet leaves the Home Screen visible behind the app, which no iOS app does.
- **Navigation:** the app still gets its own presentation context, so apps with a `NavigationStack` don't nest inside a launcher stack. The Home Screen has no `NavigationStack`.
- **Fallback:** `Runner.presentation` is a flag that can be `.zoom` or `.sheet` (`.presentationDragIndicator(.visible)`, `.large` detent). If the iOS 26 zoom bugs in §0 still reproduce on the iOS version in use, the flag switches to the sheet. That is one line, and the rest of the runner is unchanged.
- **Drag conflicts:** apps with their own vertical drag gestures can fight the dismiss gesture. Dragging down from the top 44pt (the status bar area) always dismisses, enforced with a small overlay `DragGesture`.
- **Background:** the runner sets `.background(Color(.systemBackground))`, because many Kiln apps leave the background transparent.

### 6.2 Running

```swift
@State private var result: KilnResult?
.task(id: app.version) { result = Kiln.run(SourceRewriter.isolate(source, slug: app.slug)) }
```

- The app runs once per open and once per version, so a sync during a session swaps in the new code only after the user closes and reopens the app. The same is true on iOS.
- Opening an app clears its blue dot.

### 6.3 `SourceRewriter`

- **Rewrite:** `@AppStorage("key")` becomes `@AppStorage("<slug>.key")`. It uses one regex on string literals in the attribute position only.
- **Tests:**
  - the plain form
  - `@AppStorage("k", store: …)`
  - an occurrence in a comment or a string elsewhere, which must stay untouched
- **Cleanup:** when an app is removed, `UserDefaults.standard` keys with the prefix `kiln.app.<slug>.` are deleted.

---

## 7. Errors

| Where | What the user sees |
|---|---|
| Compile error (`result.view == nil`) | `ErrorScreen` inside the runner. |
| Error inside the running app | Kiln's own inline label. Shelf can't intercept these. |
| Source file missing (deleted from the cache, or interrupted on the first sync) | The icon shows the install pie and fetches the source on tap. Offline, the icon is dimmed and shakes when tapped. |
| Sync | The banner in §4. |

`ErrorScreen` shows the app's icon at 60pt and the line "{name} couldn't open". Below them, the code around the failing line:

- The line number is parsed with the regex `^Line (\d+):` from the error string.
- Lines N−2 to N+2 are shown in a monospaced block, with line numbers in the gutter and the failing line on a tinted background.
- Kiln's message appears beneath the block.

When there is no line number, only the message is shown. The screen has no other text and no buttons; dragging down closes it.

---

## 8. Build order

Each step ends in something that can be run.

1. **ij5.dev:** migration, `apps.ts`, API and tests. Deploy, then add one app with `curl`.
2. **shelf:** XcodeGen project, Kiln package and models. A test runs `Kiln.run` on a fixture.
3. `SyncEngine` with `URLProtocol` stub tests for 304, a partial failure, a deleted app, a `401` and offline.
4. A plain Home Screen: wallpaper, grid, icon, label, and the runner with the zoom transition. A real phone starts using it here.
5. The dock, Settings and the connect flow.
6. The detail pass: pressed state, blue dot, install pie, banner, dark icons, search pill and search.
7. Edit mode: jiggle, drag to reorder, dock pinning and paging.
8. The error screen and `SourceRewriter`.
9. **ij5.dev:** the admin editor.
10. The overlay pass (§9) and an accessibility pass with VoiceOver, the largest text size, Reduce Motion and Increased Contrast.

---

## 9. Checking the details

- **Metrics:**
  - Screenshot Springboard and Shelf with the same wallpaper on the same device.
  - Overlay them at 50% opacity and adjust icon size, insets, row distribution, label offset, dock inset and radius until the edges line up.
  - Repeat on the smallest and largest supported iPhones.
  - Write the final numbers back into `HomeMetrics.swift`, the one place they live.
- **Motion:**
  - Record both screens at 60 fps and compare frame by frame:
    - app open and close
    - jiggle period
    - icon press darkening
    - the spring on reordered icons
  - Compare the curves, not just the durations.
- **Dark mode, tinted wallpaper and Increased Contrast:** check each the same way.

---

## Later

- Run `Kiln.validate` before an app can be saved. Validation needs Swift, so it runs either in Shelf as a "Check" action against a sandboxed copy of the app's storage, or in a small macOS CLI.
- Home Screen shortcuts per app through App Intents (`OpenShelfAppIntent` with an `AppEntity` per app), and Spotlight indexing through `IndexedEntity`.
- A read-only token: `APPS_TOKEN_HASH` on the server, accepted only by `GET /api/apps*`, so the phone never holds the admin token.
- Native bridges with `Kiln.register` (haptics, opening a URL), documented in the admin page for authors.
- Widgets that open an app directly.
