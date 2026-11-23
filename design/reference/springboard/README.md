# Springboard reference captures (iPhone 17, iOS 27.0 simulator)

Captured from simulator "Shelf Tests 2" (`1436DB78-…`), 402×874 pt @3x, stills 1206×2622. Driven only through `agent-device`.
Everything below is **over the simulator's stock wallpaper, which is plain black** (see "Not captured" for the photo wallpaper). Because the wallpaper is black, the glass dock and pills look darker and flatter than they do over a photo; use `real-device-*` for how they look over a photo, with the caveat below.
Default text size ("Large"), default icon style, default (not tinted) appearance unless the file name says otherwise. Page 1 has two widgets (Maps, Calendar, rendered as blank white squares in the simulator) plus two rows of 4 icons; page 2 has 9 icons; the Today View sits one page to the left of page 1. In edit mode a third, empty page is added (page control reads "Page 1 of 3").

## Reading the recordings

* Recordings were made with `record start --scope device --fps 60` (simctl video). The MP4s are **variable frame rate**: frames only exist while pixels change. During motion the gap is ~15–18 ms (≈60 fps); static periods have no frames at all (so `ffprobe` "duration" includes long idle gaps, and the avg fps is meaningless).
* So the `*-frames.png` sheets are **not** fps-resampled. Each cell is one real video frame, labelled `#index +ms` where `+ms` is that frame's presentation time relative to the first frame of the sheet. Leading and trailing frames where nothing changes are trimmed. Frame-level numbers in the notes below (frames / ms) come from these labels. A few frame gaps are 3–8 ms (bursty capture) so treat ms as ±10 ms.
* The simulator is not a real device; its animation curves are Apple's own, but timing under load can differ a little from hardware.
* `*.gesture-telemetry.json` next to an MP4 is agent-device's log of the injected touches (tap/swipe, start xy in pt, duration). It is on a different clock from the video's pts; I did not verify the offset.

## Stills

| File | State | How produced | Notable |
|---|---|---|---|
| `home-page1-light.png` | Home Screen page 1, light appearance | `settings appearance light`, `gesture pan` to page 1, `screenshot --pixel-density 3` | Status bar 10:32 (white text on black). Two 164×164 pt widgets (blank white in simulator) then 2 rows of icons. Icons **64 pt**, column centres ≈ 62 / 155 / 247 / 340 pt (pitch ≈ 93), row pitch ≈ 100 pt incl. label, left/right margin ≈ 30 pt. Search pill **78×30 pt**, y 704–733, centred, ~20 pt above dock. Dock x 17–385 (368 wide) × y 754–857 (103 tall), ~17 pt side inset, ~17 pt from bottom edge, large continuous corner radius (looks ≈ 40–45 pt, nearly a pill). Dock icons 64 pt. |
| `home-page2-light.png` | Page 2, light | swipe left from page 1 | 9 icons (Fitness, Watch, Reminders, Files / Preview, Utilities folder, Contacts, Shelf / a test-runner app whose label truncates to "AgentDeviceRu…" — ellipsis truncation). Search pill, not dots, at rest. |
| `home-page1-dark.png` | Page 1, dark appearance | `settings appearance dark` | Icons switch to their dark variants (Calendar, Health, Photos, etc. get dark backgrounds), labels unchanged white, widgets unchanged. Dock/pill unchanged on black wallpaper. |
| `home-page2-dark.png` | Page 2, dark | same | Same layout; Files, Reminders, Contacts, Preview, Shelf switch to dark glyph tiles. |
| `edit-mode-page1-light.png` | Edit mode ("jiggle") page 1 | long-press empty wallpaper 1.2 s | Top bar: **brush ("Edit"/customize) button top-left, checkmark ("Done") top-right**, each a ~66×28 pt dark glass pill, y 19–47; status bar (clock etc.) is hidden. **Minus badge** (≈25 pt grey circle, white "−") on the top-left corner of every icon, widget and dock icon, centred ≈2–3 pt inside the icon's corner. Widgets get a resize handle bottom-right and a darker outline. Search pill replaced by **page dots** (3 dots: 2 pages + new empty page). There are no notification count badges in the simulator; see real-device images for those. Still is one phase of the jiggle. |
| `longpress-menu-grid-photos.png` | Long-press on a grid icon (Photos) | `longpress 155 323 1500` | Lifted icon is ≈15% larger and fully bright; **everything else dims to ~80% grey** (widgets become light grey, labels of other icons stay legible). Quick-action menu (blurred glass, rounded ≈ 26 pt): Most Recent, Favorites, Search, Edit Home Screen, Remove App (red, last). Menu opens below the icon, left edge aligned near the icon. Lifted icon's own label is covered by the menu. |
| `longpress-menu-dock-safari.png` | Long-press on a dock icon (Safari) | `longpress 157 805 1500` | Menu opens **above** the dock icon (Remove App, Edit Home Screen — only 2 items for Safari here). Dock itself and the other dock icon dim; lifted icon pokes above the dock. |
| `home-page1-light-text-xxxl.png` | Largest standard text size (Extra-Extra-Extra-Large) | `settings text-size extra-extra-extra-large` | **Labels grow (~+15–20 %); the grid, icon size, spacing and dock do not change.** Longer names ellipsize earlier. Search-pill text did not change visibly. |
| `home-page1-light-text-accessibility-xxxl.png` | Largest accessibility size | `settings text-size accessibility-extra-extra-extra-large` | Looks identical to XXXL — the Home Screen caps label size. Device was reset to "large" (default) afterwards. |
| `icon-pressed-state-still.png` | Frame extracted from `icon-press-lift-menu.mp4` at t=3.12 s | `ffmpeg -ss 3.12 -frames:v 1` | Full-res still of the **pressed** (touch-down, before lift) state of Photos. |
| `closeup-icon-with-label.png` | Photos icon + label, rest state | PIL crop of `home-page1-light.png` (x330–600, y830–1150, full res) | 64 pt icon, ≈ 4–6 pt gap to a single-line label, label ≈ 12–13 pt medium weight white. |
| `closeup-icon-pressed-state.png` | Same icon, pressed | crop of `icon-pressed-state-still.png` | **Icon dims to ~55 % brightness (grey wash over the whole tile, glyph included), same size, label unchanged.** |
| `closeup-icon-lifted-longpress.png` | Same icon, lifted for the menu | crop of `longpress-menu-grid-photos.png` | Scaled ≈1.15×, full brightness again, soft shadow; menu starts right under it. |
| `closeup-dock-left-corner.png` | Dock left end + first icon | crop of `home-page1-light.png` | Large corner radius, 1 px lighter hairline edge, dark translucent fill. |
| `closeup-search-pill.png` | Search pill (rest) | crop of `home-page1-light.png` | Dark glass pill, magnifier + "Search" in grey. |
| `closeup-page-dots-edit-mode.png` | Page dots in the pill (edit mode) | crop of `edit-mode-page1-light.png` | 3 dots (first white = current, others grey), same pill size as the search pill. At rest outside edit mode the dots are **not** shown (pill says "Search"); they only appear while paging and in edit mode. |
| `closeup-edit-badge-icon.png` | Minus badge on an icon | crop of `edit-mode-page1-light.png` | Grey circle with dash, top-left of the icon. |
| `closeup-edit-badge-dock.png` | Minus badges on dock icons | crop of `edit-mode-page1-light.png` | Same badge on the dock icon's top-left corner. |
| `closeup-edit-buttons.png` | Top buttons in edit mode | crop of `edit-mode-page1-light.png` | Left pill: brush/"Edit" glyph. Right pill: checkmark. |

## Recordings (60 fps capture; frame sheets alongside)

| File | State | How produced | Notable |
|---|---|---|---|
| `app-open-close.mp4` | Tap Settings icon → app opens; later Home → app closes | `record start`, `press 340 423`, wait, `home` (see "Not captured": a swipe-up from the bottom edge cannot be injected) | Contains one open and one close. |
| `app-open-frames.png` | Open, every frame (38 frames, 455 ms) | frame sheet of the open | Frame 0: Settings icon pressed/dim. #1 (+7 ms): a small rounded card (≈ 40 % of screen width) already floating at the icon; background Home Screen **blurs** immediately. Card grows to full screen by ≈ #12 (+173 ms), rounded corners that stay rounded (≈ device corner radius) until the very end, content below the status bar fades in over the card; the dock and Search pill blur out and fall away. Remaining ~280 ms is settling (status bar/Dynamic Island content arrives, last frames identical). Owner said the open animation need not be matched exactly. |
| `app-close-frames.png` | Close, every frame (21 frames, 320 ms) | frame sheet of the close | #0: full-screen card with rounded corners. The card **shrinks toward its icon** while corner radius grows with it (becomes the icon's rounded square by ≈ #8, +127 ms), content cross-fades to the icon artwork (≈ #6–#8). Home Screen behind starts **blurred and dim and smaller**: widget width measured **118 pt at +167 ms vs 157 pt settled → ≈ 0.75× scale** growing to 1.0 with ease-out by ≈ +300 ms; blur clears by ≈ +200 ms (#13); dock and Search pill come back sharp last. |
| `icon-press-lift-menu.mp4` | Touch-down on Photos, hold 1.5 s | `record start`, `longpress 155 323 1500` | Shows touch-down → pressed → lift → menu. |
| `icon-press-lift-menu-frames.png` | Crop of the icon area, 36 frames (527 ms) | frame sheet | Pressed state appears at once (≤ 10 ms): the **icon tile dims to ~55 % grey and does not scale**. It stays like that ≈ 400 ms, then at ≈ #29–#35 (+430–530 ms) it brightens back to full and scales up ≈ 1.15× (the "lift"), while the rest of the screen dims and the menu fades in. |
| `icon-press-lift-menu-fullscreen-frames.png` | Same, full screen | frame sheet | For context (menu not yet visible in this window). |
| `edit-mode-enter-exit.mp4` | Long-press empty wallpaper → jiggle ≈ 3.5 s → tap Done | `longpress 200 600 1200`, wait, `press 332 33` | The jiggle is continuous (273 frames at 60 fps over 3.5 s). Exit follows ~0.9 s of motion. |
| `edit-mode-enter-frames.png` | Entering edit mode (50 frames, 668 ms) | sheet | Time/status bar fades out, top buttons fade in at the same time (≈ +90 ms), minus badges fade in, **Search pill crossfades to page dots by ≈ +60–90 ms**, icons begin the jiggle (small rotation, alternating phase per icon), dock icons get badges too. |
| `edit-mode-exit-frames.png` | Exit (26 frames, 830 ms) | sheet | Badges and buttons fade out, jiggle stops, status bar returns, page dots crossfade back to "Search". |
| `page-swipe.mp4` | Page 2 → 1 → 2 | `gesture pan 50 500 300 0 500`, then `gesture pan 350 500 -300 0 500` | Native horizontal paging; the pill shows dots while the pager is moving, "Search" at rest. |
| `page-swipe-1-to-0-frames.png` | Swipe from page 2 to page 1 (69 frames, 805 ms) | sheet | The Search pill turns into **two page dots as soon as the page starts moving** and keeps them until it settles, then reads "Search" again. Icons move with the finger, no scale/dim during paging. |
| `page-swipe-0-to-1-frames.png` | Swipe from page 1 to page 2 (56 frames, 737 ms) | sheet | Same behaviour in the other direction. |

## Real-device recording: swiping up to close (PLAN.md §0.7)

| File | State | How produced | Notable |
|---|---|---|---|
| `real-device-open-close-swipe-up.mp4` | Springboard on the owner's iPhone 17 (iOS 27), dark-mode apps opened and closed with swipes up from the home indicator | iOS screen recording, 1206×2622 (3x), tagged 120 fps but about 60 (1247 frames in 21 s, 16.7 ms apart, a few dropped) | Opens and closes GitHub, Settings, Developer and Weather. **Measured from:** Settings, closes at 6.95 s and 8.70 s (icon column 1, row 4); Developer, closes at 12.80 s and 14.85 s (column 3, row 5, centre (248, 523)). The GitHub ones (1.4–4.8 s) were laggy and aren't used. |

**Method.** Every frame of each close, at full resolution, with its real pts (`ffmpeg -vf select='between(t,…)',showinfo -vsync 0`). Both apps are in dark mode with a black background (luminance 0–3), and nothing behind the card is that dark, so the card is the black region: its edges per row give its width, height, centre and, row by row, its outline. Once the card has crossfaded to its icon, the Developer tile is tracked by its blue. A screen recording doesn't show the finger, so the finger's travel is inferred: it starts on the card's bottom edge, which rises with it before release. "SB" is Springboard; times are from the first frame that moves.

**While the finger is down** (the four closes agree; Developer 12.80 s shown):

| ms | top | bottom | width ÷ 402 |
|---|---|---|---|
| 17 | 6 | 865 | 0.987 |
| 33 | 19 | 833 | 0.934 |
| 50 | 27 | 815 | 0.904 |
| 67 | 63 | 765 | 0.827 |

- The width falls by 0.0016 of the screen per point the bottom edge rises, steadily through the first 135 points (Settings: 0.972 at 31 pt, 0.949 at 47, 0.894 at 65, 0.823 at 113). That's `RunnerMetrics.trackTravel` 0.5 with the floor at 0.3.
- **The top edge only ever moves down**, 0.3–0.5 points per point the finger rises, in all four. It never rises above where it started. These are flicks released by 0.82 of the screen's width, so the limit itself isn't reached here: `trackEdge` (the screen's top) and `trackResistance` (62 pt) are inferred, not measured. See "Still to record" below.
- It stays centred horizontally, give or take the finger's own sideways drift (+21 pt for Developer, whose icon is to the right).
- The outline keeps the display's corners (about 55 pt) the whole way down to about twice the icon's size: the bottom-left corner is still inset 7 pt at 32 pt up when the card is 222 pt wide. So does Shelf's now (`CardMotion.cornerRadius`).

**After the finger lets go** (Developer, 14.85 s; released at about 33 ms with the card 376 × 748, its width shrinking at 2160 pt/s, its height at 4900 pt/s, its centre moving up at 450 pt/s and right at 240). Shelf's column is its flight (`Motion.cardClose`) started from that same state:

| ms | width SB / Shelf | height SB / Shelf | centre x SB / Shelf | centre y SB / Shelf |
|---|---|---|---|---|
| 50 | 340 / 338 | 666 / 658 | 207 / 208 | 426 / 431 |
| 67 | 299 / 300 | 556 / 564 | 212 / 213 | 438 / 435 |
| 83 | 278 / 265 | 499 / 480 | 215 / 218 | 442 / 442 |
| 100 | 239 / 231 | 400 / 398 | 220 / 223 | 451 / 451 |
| 167 | 123 / 131 | 158 / 181 | 238 / 237 | 493 / 486 |
| 200 | 102 / 102 | 124 / 127 | 242 / 241 | 503 / 499 |
| 233 | 83 / 83 | 95 / 95 | 245 / 243 | 512 / 507 |
| 267 | 71 / 71 | 77 / 77 | 246 / 245 | 518 / 513 |
| 300 | 65 / 65 | 67 / 69 | 248 / 246 | 521 / 517 |
| 317 | 62 / 63 | 65 / 66 | 248 / 246 | 522 / 518 |

- Each property was fitted on its own (least absolute error over these frames): width 0.44 s with bounce 0.16, height 0.35 s with 0.10, centre x 0.46 s with 0.2, centre y 0.38 s with 0.16, mean errors of 2.6, 5.4, 0.5 and 1.1 pt. Shelf takes the centre at 0.38 s with bounce 0.05, which fits as well (1.3 and 3.7 pt) and never overshoots an icon below.
- **The card doesn't fly at the icon.** Its centre keeps the little speed it had (here up, at 450 pt/s, so it rises 8 pt) and stays near the middle of the screen while it shrinks, then glides into the slot. Its height closes faster than its width: portrait (2.0) at release, 1.7 at 100 ms, square as it lands.
- ~~**The picture is stretched, not cropped.**~~ **Corrected in §0.8:** the picture is drawn at the card's width from its top and cropped at the bottom, closing as opening, and the glyph keeps its shape. In the Developer close at 15.04 s "Sign Out" sits 0.88 of the way down the card, where a width-fitted picture puts it (0.87), not 0.63 where a squashed one would; the home indicator at the card's bottom is the system's own, drawn on the card, which is what read as "the whole app shows". The glyph is where it would be on a square icon at the card's top (its centre within about 5 pt of that through the Developer close at 15.0 s).
- **The crossfade** from the app to its icon takes two frames, at about 0.4 of the way from icon to screen width (`RunnerMetrics.contentFade` 0.28–0.42).
- **It leans toward an icon below.** For both Developer closes (icon about 100 pt below the card) the card's bottom edge is narrower than its top, by 0.7% at 33 ms, 2.8% at 50, 4.7% at 67, 5.6% at 83 and 7.8% at 100: a lean back about its horizontal axis, growing as it closes. For both Settings closes (icon level with the card) there is none (within ±0.5%). Shelf leans by `RunnerMetrics.landingLean` (fitted, 50° per unit of drop over card height × progress lost), at most 8°, with a 500 pt perspective.
- **Behind it**, the settled Home Screen, scaled, blurred with a Gaussian and darkened, was fitted to each frame (outside the card):

  | ms | card progress | scale | blur σ (pt) | brightness |
  |---|---|---|---|---|
  | 50 | 0.82 | 0.90 | 20 | 0.5 |
  | 67 | 0.69 | 0.95 | 20 | 0.5 |
  | 100 | 0.52 | 0.90 | 16 | 0.7 |
  | 167 | 0.17 | 0.95 | 8 | 0.8 |
  | 217 | 0.08 | 0.95 | 4 | 0.9 |
  | 367 | 0 | 1.0 | 2 | 1.0 |

  So the blur is a real radius that shrinks with the card, not a fade (`RunnerMetrics.backdropBlurRadius` 20 pt, full down to 0.45 progress), and the dim lightens all the way down (`backdropDim` 0.5, as progress to the 0.6). Shelf draws it with §0.3's `BackdropView`.

**Compared on the simulator.** A flick on Shelf (Packing, the same slot as Developer) recorded with `agent-device record` and laid beside the Developer close frame for frame: the card shrinks almost in place with the display's corners, crossfades at about 1.5× the icon to a stretched glyph, glides down into the slot and lands on it, while the Home Screen comes into focus. XCTest's injected pan isn't a finger (it moves in jumps and its release speed is its own), so the timing is judged by the table above, not by that recording.

## Real-device recording: opening (PLAN.md §0.8)

| File | State | How produced | Notable |
|---|---|---|---|
| `real-device-open-close-swipe-up.mp4` | as above | as above | **Measured from:** the opens of Settings at 6.2 and 7.95 s (column 1, row 4, level with the card), Developer at 11.55 s (cold: black, then the Account screen) and 13.85 s (resumed: its snapshot), Weather at 16.75 s (cold: its blue launch screen, then content). Both Settings opens trace the same sizes frame for frame. |
| `real-device-photos-open-close.mp4` | Springboard on the owner's iPhone 17, Photos (top-right corner) opened and closed several times, dark mode | iOS screen recording, 1206×2622, ≈60 fps | The sideways lean: **measured from** the close at 2.05–2.5 s and the open at 1.3–1.4 s. |

**Method.** As for the closes: every frame at full resolution with its pts. A black card (dark mode, cold or Settings) is found by flood fill over pixels under 8–10 of 255 on a 1-pt grid. Where an app's content breaks that (the resumed Developer, Photos' share sheet), the outline is read off a 10-pt grid over the full-resolution frame. The backdrop is fitted as for the close (the settled Home Screen, scaled, Gaussian-blurred, darkened) on strips the card never covers.

**The growth** (Settings at 6.2 s; a frame of the recording repeats at 6.218, so the times are the frames' pts; Shelf's column is `Motion.cardOpen` started from the icon 28 ms before the first frame):

| ms | width SB / Shelf | height SB |
|---|---|---|
| 0 | 111 / 111 | 142 |
| 33 | 180 / 193 | 276 |
| 50 | 225 / 235 | 381 |
| 67 | 266 / 270 | 482 |
| 83 | 300 / 299 | 574 |
| 100 | 328 / 323 | 650 |
| 133 | 363 / 356 | 755 |
| 167 | 382 / 378 | |
| 200 | 393 / 390 | |

- **Critically damped**, the width and the centre on about 0.29–0.3 s, the height on about 0.33 s: the card is squat as it grows (1.7 high per wide at half the screen's width, 2.0 at 0.8) and reaches the screen's shape last. The Developer opens trace the same widths 7 ms earlier. The first frame of every open is already 0.14–0.3 of the way: the recording loses a frame or two as the app launches.

**The icon gives way to the surface** early (the icon's share of what the card shows, judged from its glyph's contrast):

| open | width | progress | icon |
|---|---|---|---|
| Settings 6.2 | 111 | 0.14 | all |
| Settings 6.2 | 180 | 0.34 | ≈ 15% |
| Settings 6.2 | 225 | 0.48 | ≈ 0–5% |
| Developer 11.55 | 169 | 0.31 | ≈ 15% |
| Developer 11.55 | 192 | 0.38 | ≈ 7% |
| Developer 11.55 | 238 | 0.51 | none |
| Developer 13.85 | ≈ 170 | ≈ 0.31 | ≈ 25% |
| Developer 13.85 | 227 | 0.48 | ≈ 5% |

  So `RunnerMetrics.launchFade` is 0.12–0.5, easing out (a quarter left at 0.31, a tenth at 0.38). The close's crossfade (two frames at about 0.4) is later and shorter.

- **The surface is drawn at the card's width, from its top**, cropped at the bottom, not squashed: at 13.85 s with the card 350 wide (0.87 of the screen), "Sign Out" is 12.3 pt tall (14.3 full screen, × 0.86) at 567 pt, where a width-fitted picture from the card's top puts it (566), not where a squashed one would (519). The status bar and the home indicator are drawn on the card from its first frame. The icon's glyph keeps its shape too, scaled by the card's width and sitting where it would on a square icon at the card's top (Weather's cloud, Developer's "A").
- **Behind it**, the Home Screen blurs late and darkens early, unlike the close:

  | progress | blur σ (pt) | brightness |
  |---|---|---|
  | 0.14 | 2 | 0.91 |
  | 0.48 | 3–4 | 0.80 |
  | 0.60 | 4 | 0.75 |
  | 0.66 | 6–10 | 0.68 |
  | 0.75 | 8–14 | 0.62 |
  | 0.82 | 16 | 0.59 |
  | 0.87 | 18 | 0.55 |

  Shelf: blur 20 × progress² (`openBlurCurve`), dim 0.5 × progress. Its scale stays within 2% of 1 on the strips measured.
- **It leans away from its icon**, as the landing leans toward it. The cold Developer open (icon about 60 pt below the card's centre): the bottom edge is narrower than the top by 4.8% at 0.51, 4.1% at 0.63, 3.7% at 0.73, 3.1% at 0.80, 2.6% at 0.86, 1.7% at 0.90, which is 1.3–1.6 radians per unit of (the icon's drop in card heights) × (1 − progress) (`launchLean` 1.4). The Settings opens, level with their icon, don't lean.
- **And sideways.** The Photos close at 2.45 s (card 197 × 293 at (288, 290), its icon at (343, 126)): the top is 2.5% narrower than the bottom (about 0.06 rad), and the right edge is 2.3% taller than the left (about 0.086 rad): the side away from the icon goes back. Its opens turn the same way (the top-left corner farthest). `sideLean` 0.65 per unit of (the icon's offset in card widths) × (progress lost, landing; still to grow, opening). One close, so fitted, not checked across the grid.
- **The app replaces its launch screen** with a crossfade (Weather at 17.19 s, the blue channel of the middle of the screen going from the launch screen's to the app's): 2% at 17 ms, 15% at 50, 39% at 83, 59% at 117, 74% at 150, 88% at 200, 93% at 233, done by 330. A critically damped spring of 0.38 s (`Motion.launch`).

**Compared on the simulator.** Weather (grouped list, `NavigationStack`) opened cold and from its snapshot, light and dark, at normal speed and at a quarter speed (`-ShelfSlowMotion 4`), and opened and closed from the top-left, top-right, middle-left and dock places: the icon gives way to the surface by half way, the glyph keeps its shape at the top of the card opening and closing, the card leans by where its icon is, and the app crossfades in over the surface with nothing between. Before §0.8 the tint and a white glyph filled the card until the app was built, and the blurred Home Screen showed for 2–5 frames between that and the app.

### Still to record: a slow, long swipe

The limit and the resistance are inferred. To measure them, record on the iPhone 17:

1. **Set up.** An app with a black background in dark mode (Settings), Settings › Accessibility › Display & Text Size › Reduce Motion **off**, Control Center's Screen Recording.
2. **The swipe.** From the home indicator, straight up the middle, slowly and evenly, over about 2 seconds, to about 100 pt below the top of the screen. Hold still for half a second, then lift without flicking. Make three of these. Then three that go up the same way and come back down to the bottom edge before lifting (the cancel).
3. **The finger.** A screen recording can't show it. Either film the phone at the same time with a second phone in slow motion (240 fps, finger and screen both in frame; clap once at the start to line the two up), or swipe along a ruler at an even speed, counting, so the finger's height can be taken as a straight line between touch-down (the card's first frame of motion) and lift (the first frame the card moves on its own).
4. **Frames.** `ffmpeg -i swipe.mp4 -vf "select='between(t,START,END)',showinfo" -vsync 0 frames/%04d.png 2> frames/info.txt`, and the pts from `info.txt` (`pts_time`), never frame number ÷ 120.
5. **Per frame.** The card's top, bottom, left and right: the rows and columns where the black background (luminance ≤ 3) spans more than 40 pixels, ignoring the Dynamic Island's band (the top 130 px, x 380–830).
6. **Plot** against the finger's travel (its starting height less its height now):
   - the card's top edge: it falls at first, then rises. It should flatten toward a line: that line is `trackEdge`, and the travel at which it departs from the path a card held at the finger would take gives `trackResistance` (with Shelf's band, the remaining distance d goes to d² / (d + overshoot));
   - the width ÷ 402: its slope near zero should still read 0.0016, and where it levels off is `trackMinScale`;
   - the bottom edge against the finger: where they part is where the finger stops holding its point on the card.
7. **Keep** the recordings here as `real-device-swipe-slow-*.mp4` (they stay out of git), add a row to this table, and replace the inferred constants in `Shelf/Runner/RunnerMetrics.swift` with the measured ones, noting the clip.

## Real-device screenshots supplied by the owner

These were pasted in during the session; they are **not** from the simulator and they are **not at default Liquid Glass settings** (owner said so), so don't match dock/pill/menu *materials* to them. Use them for: layout, **notification badge** placement/size, 4-icon dock, widget rendering, long-press menu structure (icon-size picker row for widgets, Remove App / Require Face ID / Share App / Edit Home Screen), edit-mode chrome. Photo wallpaper in these is *not* the Shelf wallpaper. Images are 920×2000 (downscaled by the sender).

| File | State | Notable |
|---|---|---|
| `real-device-home-page1.png` | Page 1, no labels visible on the grid at this size | Red notification badges (1, 5,347, 2, 59, 3, 30) hang off the icon's **top-right** corner, centred on the corner, height ≈ 24 pt, pill shape that widens with digits. |
| `real-device-home-page1-b.png` | Same, later moment | Same. |
| `real-device-home-page1-with-labels.png` | Page 1 with labels | Labels, badges, a small widget with a label under it ("Fitness"), a "• Rex Dev" label with a dot. |
| `real-device-edit-mode.png` | Edit mode on that device | Brush + check buttons; minus badges at top-left of each icon and of the widget; page dots in the pill; vertical page indicator beside the widget (widget-stack dots). |
| `real-device-edit-mode-b.png` | Edit mode, a moment later | Same; shows the jiggle phase differing per icon. |
| `real-device-longpress-menu-calendar.png` | Long-press on Calendar | Lifted icon, menu above with quick actions + a row of widget-size buttons. |
| `real-device-longpress-menu-settings-style.png` | Long-press menu with Remove App / Require Face ID / Share App / Edit Home Screen and the widget-size row | The menu opens *beside* the lifted icon, and everything else dims. |
| `real-device-extra-2.png` | Long-press menu on a different icon (Developer) with labels visible | Same menu style; the other icons' labels are dimmed along with the icons. |
| `app-library-search.png` | App Library search (framed mockup of a real device, scaled) | The target for Shelf's search (PLAN.md §0.3): field and round ✕ on top (Shelf puts them at the bottom), letter sections, icon + name rows with hairline separators from the name's edge, a cloud glyph for apps not downloaded, the A–Z # index on the right, over a heavily blurred, darkened Home Screen. Structure only; measure from a simulator capture. |
| `glass-icon-1.png` … `glass-icon-4.png` | Four iOS 27 Home Screen icons, close up | The look Shelf's icons should get (PLAN.md, Glass icons): rim highlight, light at the edges, depth in the glyph. Capture fresh ones from the simulator before copying details. |

## Not captured, and why

* **Photo wallpaper (owner's follow-up request): impossible on this simulator.** `simctl addmedia` worked (the photo is in Photos as the last of 7 items; I confirmed it's the Shelf photo). But: (1) Settings has no Wallpaper entry (a Settings search for "Wallpaper" returns "No Results"); (2) Home Screen → long-press → Edit → **Edit Wallpaper** shows a spinner for ~5–40 s and then drops back to the Home Screen without presenting a picker (tried 3×); (3) Photos → open photo → Share → **Use as Wallpaper** appears in the share sheet but its icon never leaves the loading placeholder, tapping it does nothing (tried by ref, by coordinates, and a short long-press, waited 10+ s). The wallpaper service on this simulator image does not seem to be functional, so all captures keep the stock black wallpaper, as the owner said to do in that case.
* **Customize panel and the Dark / Clear / Tinted icon styles:** Home Screen → Edit → **Customize** shows the same spinner for several seconds and falls back to the plain Home Screen (tried 3×, watched with frequent screenshots). No Customize panel stills and no icon-style stills (Default, Dark, Clear, Tinted). The only icon variants available are the Default ones, and Light/Dark appearance (see `home-page1-dark.png`).
* **Swipe-up-from-the-bottom close (quick or slow), and the cancel-and-return variant (items 8 close, 9):** agent-device injects touches via XCTest in the foreground app's frame, so a swipe starting at y=870–874 only scrolls the app (Settings scrolled) and never triggers the system home gesture (tried `gesture pan`, `swipe`, `gesture fling` from y 866–873; y=874 is rejected as outside the viewport). Therefore the finger-following close and the cancel version could not be recorded here; the owner recorded swipe-ups on an iPhone 17 instead (`real-device-open-close-swipe-up.mp4`, above), and a slow, long swipe is still to record. The quick close in `app-open-close.mp4` was made with the `home` command (the system's own close transition; it plays the same card-shrinks-into-icon animation as the quick swipe-up, but it is not finger-driven). To learn how the card follows the finger, use the close sheet only as the "fast, released" case; the finger-tracking behaviour is not documented here.
* **Dragging an icon to another slot / into the dock (item 12):** `gesture drag` in edit mode did not pick up the icon: a 150–300 ms hold + move turned into a page swipe, and a ≥ 600 ms hold triggered the quick-action menu instead of a pick-up. Tried five variants and one crashed the XCTest runner (restarted). No usable recording, so no sheet. Not recorded: icons sliding aside, drop into the dock.
* **A press that does *not* launch** (item 10): a 350 ms `longpress` launches the app (it was too short to count as a hold), a ≥ 600 ms one lifts the icon and opens the menu. So the pressed state is shown as the first ~400 ms of `icon-press-lift-menu.mp4` (touch-down is held for that long before the lift), which is the real behaviour for a long touch.
* The Today View (one page left of page 1) was seen but not captured as a still. Edit-mode "jiggle" amplitude is not measured (no rotation values), only visible in `edit-mode-enter-exit.mp4`.
* Spotlight / Siri / App Library were deliberately not opened.
* Side effects on the simulator: the Photos app was opened once (its first-run "What's New" sheet and a notification-permission alert were dismissed, permission was *not* allowed); a first-run keyboard "Continue" sheet in Springboard was dismissed. One photo (the Shelf wallpaper) was added to the Photos library.

## Most useful observations for rebuilding

1. **Metrics (pt):** icon 64, column pitch ≈ 93, row pitch ≈ 100 with label, side margin ≈ 30; dock 368×103 at 17 pt inset, 17 pt from bottom; dock icons 64; search pill 78×30, centred, 20 pt above dock.
2. **Pressed state:** touch-down dims the icon tile to ~55 % (grey wash, no scale) instantly; label stays. Only on a long hold does the icon lift to ≈1.15× and full brightness while everything else dims to ~80 %.
3. **Search pill ↔ page dots:** dots appear within ≈ 60–90 ms of the pager moving (and of entering edit mode), vanish back to "Search" when it settles. Same pill size/position.
4. **Edit mode chrome:** brush-left / check-right pills at y 19–47, status bar hidden, minus badge (≈25 pt) centred ~2–3 pt inside the icon's top-left corner, also on dock icons and widgets; always one extra empty page at the end.
5. **Open:** the card starts as a small rounded rectangle at the icon (~40 % width at +7 ms), reaches full size by ≈ +170 ms, with the Home Screen blurring and going away at once; corner radius stays at ≈ device radius for the card throughout. (Not essential to match, per the owner.)
6. **Close (home command):** card shrinks into the icon in ≈ 130 ms (corner radius → icon radius, artwork cross-fades in), then the Home Screen behind eases from ≈ 0.75× / blurred up to 1.0× / sharp over ≈ 200 ms more, total ≈ 320 ms. The Home Screen is **scaled down (~0.75×) and blurred while an app is up** and comes back by growing.
7. **Dark appearance** only changes the icon artwork (dark tiles) — labels, widgets and the dock don't change. Home-screen labels are always white on black; the text-size setting only enlarges labels (≈ +15–20 % at XXXL; accessibility sizes are capped to the same), the grid never reflows.
8. **Menus:** long-press dims everything else to ~80 %, lifts the icon ≈ 15 %, menu is glass with ≈ 26 pt corners and appears below a grid icon but above a dock icon; destructive "Remove App" is red and last.
9. **Real-device badges** (supplied images): red pills hanging off the icon's top-right corner, centred on the corner, ≈ 24 pt tall, widening with digits.
10. The simulator's recordings are VFR: only frames during motion exist; use the labelled sheets (real timestamps), not `fps=60` resampling.
