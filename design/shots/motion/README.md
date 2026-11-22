# Motion frame sheets

Recorded on the "Shelf Tests" simulator (iPhone 17, iOS 27.0) with
`agent-device record --fps 60`. Recordings are variable frame rate, so each
cell is one real frame labelled with its time from the first frame shown;
frames identical to the one before are dropped. Colours are reduced to keep
the files small.

| Sheet | What |
|---|---|
| `open.png` | Tap on Counter: the card grows out of the icon (its face is the icon's fill and glyph, which is the launch screen) while the Home Screen blurs and scales back behind it. The app itself appears once the data pull finishes (the dev server was down, so after its one-second timeout). |
| `close-fast.png` | A quick swipe up from the bottom edge: the card follows, then springs into the icon with the swipe's speed and lands with the icon's outline. |
| `close-slow.png` | A slow swipe up: the card tracks the finger, shrinking as it rises, then closes on release. |
| `close-cancel.png` | A short, slow swipe let go of: the card springs back to full screen and the live app returns. |
| `close-interrupted-6x-slow.png` | **Recorded with `-ShelfSlowMotion 6`** (every spring six times slower; the test driver's own latency is longer than a real close). A close is caught mid-flight, dragged down and let go: the card stops where it is, with no jump, follows the finger and springs back open. |
| `search-pull.png` | A slow pull down on the Home Screen: the pill widens toward the field as the finger moves; on release the keyboard rises and carries the field up with it. |
| `search-tap.png` | A tap on the pill plays the same warp. |
| `search-dismiss.png` | A tap outside the results: the keyboard falls and the field warps back into the pill. |
