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
