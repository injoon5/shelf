# Reference

`springboard-iphone17-ios27.png` is the real Home Screen on an iPhone 17
simulator (402 × 874 pt at 3x, iOS 27.0, light mode). The numbers in
`Shelf/Home/HomeMetrics.swift` were read out of it by finding edges in the
pixels:

| What | Measured |
|---|---|
| Icon | 64 × 64 pt |
| First column, left edge | 30.33 pt |
| Column pitch | 92.5 pt |
| First row, top edge | 90 pt (28 pt below the 62 pt status bar) |
| Row pitch | 100.33 pt |
| Label | about 13 pt; cap top 7.3 pt below the icon, baseline 16.3 pt below |
| Label, widest (truncated) | about 86 pt |
| Search pill | 78.7 × 29.3 pt, 20.3 pt above the dock |
| Dock | inset 17 pt on the sides and the bottom, 103.3 pt tall |
| Dock corner radius | about 45 pt (the display's 62 pt, less the 17 pt inset) |
| Dock icons | 64 pt, 24 pt apart, 19.67 pt from the dock's top and bottom |

To check Shelf against it, take a 3x screenshot of Shelf on the same
simulator and blend the two at 50%.

## Icon corners

Shelf's icons are not the shape Springboard's are. Measured the same way on
both (how far the left edge is inset on each pixel row down from the top of a
64 pt icon, at 3x):

| Row (px from top) | Springboard | Shelf (`iconCornerRatio` 0.2237) |
|---|---|---|
| 0 | 56 | 47 |
| 2 | 37 | 31 |
| 4 | 31 | 25 |
| 8 | 23 | 18 |
| 12 | 17 | 13 |
| 18 | 12 | 8 |
| 24 | 7 | 5 |
| 32 | 4 | 2 |
| 40 | 2 | 1 |

Springboard's corner is rounder everywhere: its diagonal inset is 15 px to
Shelf's 13, which is a circle-equivalent radius of about 17.1 pt (26.7% of the
icon) against Shelf's 14.8 pt (23.1%). The 0.2237 in the plan is the mask iOS
used through iOS 18; the icons iOS 26 and 27 draw are rounder. The shape to
match is the one in this table, wherever the icon's outline is drawn: the
fill, the rim, the pressed and pending overlays, the zoom source, and the
menu and drag previews.

Measured the same way with a threshold of 40 on a pixel over black
(`HomeViewTests.theOutlineIsSpringboards`), Springboard's Calendar tile reads
47, 35, 29, 21, 16, 11, 7, 3, 1 on those rows, and so does SwiftUI's
continuous rounded rectangle at 26%, which `IconPath` draws. A Core Animation
layer's `cornerRadius` with `cornerCurve = .continuous` reads 52, 36, 30, 22,
17, 11, 7, 4, 2: a different, rounder curve. So no icon's outline is a
layer's corner radius.

## Long press and edit mode

From `longpress-menu-grid-photos.png` and `edit-mode-page1-light.png`, at 3x:

| What | Measured |
|---|---|
| Lifted icon | 73.3 pt across for 64 (×1.146), about its own centre |
| Everything else while lifted | 80% (255 → 204, 62 → 50) |
| Menu | 250 pt wide, 8.33 pt below the lifted icon, leading edges in line |
| Menu rows | 42 pt; glyph centre 40.3 pt in, text 64.7 pt in; about 10 pt above the first and below the last |
| Minus badge | 27 pt grey disc (149, 148, 148), centre 3.67 pt in from the icon's top-left corner; dark dash 11.67 × 2 pt |
| Lift after touch-down | about 430 ms (`icon-press-lift-menu-frames.png`) |

## Search (App Library's, PLAN.md §0.3)

Measured from 3x captures of App Library search on the iPhone 17 simulator
(iOS 27.0), empty query, light and dark, driven with `agent-device`: swipe
past the last page, tap the field. The captures are kept outside git, like the
others. The numbers are in `Shelf/Home/SearchMetrics.swift`.

The simulator's App Library has no section letters, a Cancel button instead
of the round ✕, and no cloud glyphs (all its apps are installed), and its
search finds nothing when typed into (Spotlight's index isn't built there). So
the letters, the ✕ and the cloud come from `app-library-search.png`, which,
with its frame cropped off, is a 402 pt screen at 1.667 px/pt.

| What | App Library | Shelf |
|---|---|---|
| Field | 25.67 pt in (77 px), 90 pt down, 281.67 × 48 pt, capsule | Same size and inset, on the pill's line (keyboard down) or 8 pt above the keyboard |
| Magnifier | 17.33 pt of ink (132–184 px), centred 27 pt into the field, white | Same (SF magnifier at 0.84 × 22 pt) |
| Placeholder | 22 pt regular (Title 2; an "L" 47 px tall, 5 px stem), white, its "A" at 222 px | "Search", same font and colour, its "S" on the same column |
| Typed text, caret | Typed "c" at 219 px; caret 2 × 24 pt (6 × 72 px), centred on the text's start and the field | Same (`caretRect` override) |
| ✕ (reference) | A 48 pt glass circle beside the field | Same, in Cancel's place, 25.67 pt from the trailing edge, 21 pt from the field |
| Rows | 72 pt pitch (216 px between separators), first row 24 pt below the field | Same pitch; the list starts where App Library's bar does (90 pt), and its last row stops 24 pt above the field |
| Icon | 48 pt, leading edge 26.33 pt (79 px), centred in the row | Same |
| Name | 17 pt regular (Body), white, 90 pt in, centred in the row | Same |
| Separator | 1 pt (3 px), 90 pt to 371.33 pt (270–1114 px), 25/255 lighter than what's behind it (46→72 dark, 96→121 light) | White at 14% (+19…+26 over those backdrops); none under a section's last row |
| Section letter (reference) | 15 pt bold, in line with the icons, baseline 8.33 pt above the first row, in a 28.33 pt band | Same |
| Cloud (reference) | `icloud.and.arrow.down`, 19.5 pt across, 10.33 pt inside the separator's end | Same |
| Index | A–Z #, white, centred 7.67 pt from the edge (1183 px), 13.27 pt pitch (A at 1002 px, # at 2077), an "A" 20 × 22 px | 11.5 pt semibold, same pitch and column; centred on the list between its top and the field (App Library's is centred on its own list) |
| Backdrop | The Home Screen under a Gaussian blur of σ = 40 pt, then 0.854x − 14/255 (dark) or 0.837x − 22/255 (light), fitted per pixel at 1x (rms 2–3 of 255) | `CABackdropLayer` with Core Animation's `gaussianBlur` (radius 40) and a colour matrix (0.85x − 14 or 22). Fitted the same way: σ 40, 0.859x − 11.6 (dark) |
| While typing | (Can't be checked on the simulator.) App Library's results have no letters and no index | One list of matches, best first, no letters, no index; "No Results for “…”" with the system's advice line, as the simulator shows |

How a 50% overlay against App Library came out (scratch captures, not in git):
the field, magnifier, placeholder and caret coincide; the first row's icon,
name baseline and separator coincide, and later rows are one section header
(28.33 pt) apart, as the letters add; the index letters share their column and
pitch.

The backdrop darkens beyond App Library's over a wallpaper brighter than about
0.6 on average, to 0.42, so white names still read (App Library's own captures
average 0.09 and 0.27). That ceiling is Shelf's: Springboard over a white
wallpaper wasn't captured.
