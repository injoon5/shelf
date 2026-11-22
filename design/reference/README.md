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
