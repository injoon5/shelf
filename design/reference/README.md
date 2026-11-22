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
