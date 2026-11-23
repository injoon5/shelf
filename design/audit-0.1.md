# Home Screen audit (PLAN.md §0.1)

Each case in §0.1, what Springboard does (from `design/reference/springboard/`, or the plan where the captures don't show it), what Shelf did, and what changed. A case is covered by a unit test (in `ShelfTests/LayoutTests.swift` or `ShelfTests/HomeModelTests.swift`), a simulator check, or both.

**Simulator:** iPhone 17, iOS 27.0, driven only through `agent-device`. The demo library was launched with `-ShelfDemo YES -ShelfDemoFull YES`, which gives 27 apps: Habits and Todos in the dock, 24 icons on page 1, Scores alone on page 2, and Notes not downloaded.

**The SwiftUI views are about to go.** §0.2 replaces the grid, dock, drag and drop, and search results with UIKit and Core Animation. So rules live in `Layout` and `HomeModel`, where they carry over, and fixes to views were kept to the minimum. Rows marked **re-check on UIKit** need driving again once §0.2 lands.

## Layout

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| Where a new app lands | The first free slot on the last page, even with room earlier. | As expected. | None. | `newAppsFillTheLastPageThenStartAnother`, `aNewAppLandsOnTheLastPageEvenWithRoomEarlier` |
| A drop on a full page | Its last icon is pushed to the next page, cascading, and a new page starts past the last. | As expected on the simulator: Settings dropped at page 1, slot 2 pushed Dice onto page 2. | None. | `movingOntoAFullPagePushesItsLastIconOn`, `aSpillCascadesThroughFullPages`, `aSpillOffTheLastPageStartsANewOne` |
| A full dock refusing a newcomer | The dock doesn't make room. On release, the icon goes back to the grid. | **Bug.** The dock answered `.forbidden`, and the system then ends the drag without calling any `performDrop`. `dragging` was never cleared, so the icon stayed invisible (with its slot kept empty) until Done. Seen with Weather, and again with Notes. | `HomeModel.dragExited()`: when the icon leaves a drop target and no other target hears from it within `Motion.dragLost`, the drag has ended and the icon comes back. Checked on the simulator: Notes reappears where the hover left it. | `theDockHoldsFourWithSettings`, `pinningAndUnpinning`, `aDragLetGoOfOutsideEveryTargetEnds`, `aDragCrossingIntoAnotherTargetGoesOn`. **Re-check on UIKit:** §0.2's own pan recognizer ends every drag itself, so the watchdog goes with `EditDropDelegate`. |
| Dragging the only icon off a page | The page you're on stays put under the finger. | Last page: it vanished and you were left on the spare page, which looks the same. Fine. **Middle page (bug, found by reading the code and pinned by a test):** `move` dropped the emptied page at once, so every page after it shifted one place under the finger, and the next hover moved the icon onto the wrong page. | `Layout.move` keeps an emptied page until edit mode ends (`LibraryStore.finishEditing` → `removeEmptyPages`). Only empty pages at the end go, since the spare page stands in for them. `HomeModel.layoutChanged` then moves `page` and the scroll position to wherever the icons in view went. | `anEmptiedMiddlePageStaysUntilEditModeEnds`, `anEmptiedLastPageGoes`, `thePageFollowsItsIcons`, `thePagerScrollsWhenThePageInViewMoves`, `finishingEditingDropsEmptyPagesAndSaves`. **Re-check on UIKit** with three pages. The demo has only two. |
| The spare page in edit mode, and leaving edit mode with it empty | Edit mode adds one empty page (the reference reads "Page 1 of 3"). Done on it goes back to the last real page. | Before and after the fix: Done on the spare page snaps back to the last page, and the pill reads "Search" again. | `page` now follows explicitly (`page(following:)`) instead of relying on the scroll view to clamp. | `editModeAddsASparePage`, `thePageFollowsItsIcons` |

## Syncs that land mid-gesture

The demo library can't sync, so these are unit tests only.

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| An app added or deleted elsewhere during a drag | The drag goes on. Others close up, and a new icon takes the last page's first free slot. | Unit test only. | None needed. | `aDragSurvivesOtherApps`, `aSyncThatEmptiesAPageRemovesIt` |
| The dragged app itself deleted | The drag ends, and a later hover doesn't pick it up again. | **Bug (from reading the code).** `dragging` stayed set. `dragMoved()` kept returning the missing slug, and `move` quietly refused it. | `HomeModel.layoutChanged` clears `dragging` and `liftedSlug` when the icon leaves the layout. | `aDragWhoseAppIsDeletedEnds` |
| `reconcile` during a drop | The layout stays valid: no duplicates, Settings kept, and the page in view doesn't jump. | `reconcile` is idempotent and filters by ID. The page shifts when a sync removes a page before the one in view. | The page now follows its icons (see above). | `removedAndUnknownSlugsLeave`, `aSlugNeverAppearsTwice`, `thePageFollowsItsIcons` |

## Cards

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| App deleted elsewhere while its card is open | The card closes into the pill, since there's no icon. | Unit test only (no sync in the demo). Before: the card stayed open, and on close `iconFrame` could still return the stale frame. | `layoutChanged` closes the run. `StageController.close` lands in the pill when the app is gone, whatever frame SwiftUI still holds. | `anOpenAppDeletedElsewhereCloses` |
| … or caught on its way home | It must never reopen a missing app. | **Bug (from reading the code).** `StageController.reopen` sent the card back to full screen regardless. `HomeModel.reopen` just returned when another app was open, which left two cards full screen with one `run`. | `HomeModel.reopen(_:in:) -> Bool`: false when the app is gone or another app has opened. The stage then lands the card instead. | `aCaughtCardReopensOnlyIfItCan` |
| Tap on another icon while a card is closing | The new app opens. The closing card finishes landing. | Unit test only. | None. | `aTapWhileACardClosesOpensTheNewApp`. **Re-check on UIKit** with `-ShelfSlowMotion 4`. |
| Tap on an app that hasn't downloaded | It downloads and then opens. With nothing to download from, the icon shakes. | Simulator: Notes, with no server, didn't open. | **Bug (from reading the code):** a download that a later tap overtook (a tap on B while A downloads, then B closes) opened A on its own afterwards. `open` now records each tap and only opens if no later tap, edit mode or other app intervened. | `aTapOnAnAppThatHasntDownloadedRefuses`, `aDownloadThatFinishesOpens`, `aDownloadThatALaterTapOvertookDoesntOpen` |
| Quick double tap | One card. | Simulator: `press --count 2` on Habits opened one card. | None. | `aDoubleTapOpensOnce` |
| Tap during a page scroll | The tap stops the scroll and opens nothing (standard `UIScrollView`). | **Not verified.** agent-device's commands land 0.5–1 s apart, longer than a page takes to settle. In one recorded try the pan didn't page at all. | None. | **Re-check on UIKit:** §0.2's paging `UIScrollView` gets this from `UIScrollView` itself. |

## Long press

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| Menu versus drag, outside edit mode | Springboard: the menu, and moving the finger turns it into a drag (§0.2). | A long press and move on Weather opened the menu (Change…, Reload App, Copy Source, Edit Home Screen). The icon didn't move. Known, and it's §0.2's first spike. | None here. | **Re-check on UIKit.** |
| Menu versus drag, in edit mode | A long press and move drags. | `gesture drag` picked icons up and moved them every time. | None. | Simulator. |
| Long press on the wallpaper while searching | Nothing: search covers the wallpaper. | Search stayed open and edit mode didn't start. | Made explicit in the model: `HomeModel.longPressedWallpaper()` ignores it while searching. | `aLongPressOnTheWallpaperWhileSearchingDoesNothing` |
| Edit mode starting while search is open (a result's menu → Edit Home Screen) | Search closes and the icons jiggle. They never show together. | As expected (`startEditing` clears `isSearching`). | None. | `editModeFromSearchClosesSearch`, `searchDoesntOpenInEditMode` |

## Search

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| Result order | Names that start with the query, then names that contain it, each alphabetical. | "s" gave Scores, Settings, Sleep, Steps, then Bills, Flashcards… | Moved `matching` from `SearchResults.swift`, which goes in §0.3, to `HomeItem.swift`. | `searchOrder` |
| Search finds Settings | As Springboard's finds Settings. | **Before:** "No Results for “set”". **After:** "set" gives Settings, and Return opens its sheet with search closed. | `LibraryStore.items` includes `.settings`. | `searchOrder`, `settingsFromSearchClosesSearch` |
| Card from a result whose icon is on another page | It leaves past that side of the screen, at the icon's row. | **Bug.** Opened Scores (page 2) from search and swiped up: the card fell into the pill. SwiftUI reports no frame for icons on pages out of view. | `HomeGeometry.iconFrame(at:dockCount:page:)` computes the frame from the layout when none was reported. Re-recorded: the card now leaves past the right edge at the top row. | `anIconOnAnotherPageHasAFrameOffToThatSide`, `whereACardLands` |
| Card from a result with no icon | It lands in the pill. | Every app has an icon now, so only a deleted app reaches this. | See Cards. | `whereACardLands` |

## Leaving Shelf

| Case | Expected | Observed | Fix |
|---|---|---|---|
| During a drag | The drag ends, and the layout is saved. | Already handled (`scenePhase` → `endDrag`, `commitLayout`). Not re-driven. | None. |
| With a card open | Coming back shows the app as it was. | `home`, then `open`: the Habits card was still open. | None. |
| With a sheet up | Coming back shows the sheet as it was. | `home`, then `open`: Settings was still up. | None. |

## Persistence

| Case | Expected | Observed | Fix | Covered by |
|---|---|---|---|---|
| When `commitLayout` writes | On a drop, on leaving edit mode, on leaving the foreground, and after a sync that changed the layout. Never while dragging, and never signed out. | As expected. | Leaving edit mode now also drops the pages it emptied (`finishEditing`). | `aSyncThatChangesTheLayoutSavesIt`, `movesWriteOnlyWhenCommitted`, `finishingEditingDropsEmptyPagesAndSaves`, `signedOutNothingIsWritten` |
| A corrupt `layout.json` | The arrangement is lost, but no app is. | Falls back to the default: library order, Settings in the dock. The bad file is replaced at the next commit. | None. | `aCorruptLayoutFallsBackToTheDefault`, `aLayoutWithNoPagesGetsOne` |
| The layout across a relaunch | Kept. | Kept. | None. | `theLayoutSurvivesARelaunch` |
| The current page across a relaunch | Springboard starts on the first page after a restart. | Starts on page 1. `page` isn't saved, by choice. | None. | `aRelaunchStartsOnTheFirstPage` |

## Settings becomes an ordinary icon

| Rule | How | Covered by |
|---|---|---|
| Reserved ID that can't be a slug | `Layout.settings == ":settings"`. Slugs match `[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}`. | `theReservedIDCanNeverBeASlug`, `aSlugNamedLikeSettingsAddsNothing` |
| `reconcile` always keeps it | Settings is always a known ID. | `reconcileAlwaysKeepsSettings`, `anEmptyLibraryKeepsOnePageAndSettings` |
| The dock holds 4, shared with Settings | `Layout.dockSize = 4`. | `theDockHoldsFourWithSettings`, `fourDockIconsFitTheDock` |
| Starts in the dock's last place | A fresh or reset layout gains it at the end of the dock. | `settingsStartsInTheDocksLastPlace`. Simulator: dock reads Habits, Todos, Settings. |
| v1 `layout.json` migration | At the end of the dock, or at the front of the first page (pushing) if the dock is full. A damaged dock over 4 spills its extras there too. | `aV1LayoutGainsSettingsAtTheEndOfTheDock`, `aFullDockPutsSettingsAtTheFrontOfTheFirstPage`, `anOverfullDockSpillsOntoTheFirstPage` |
| Moves like any icon | Any page, or within the dock. | `settingsMovesLikeAnyIcon`. Simulator: dragged from the dock to page 1, slot 2, and back. |
| Can't be deleted | `Layout.isDeletable` and `HomeItem.isDeletable` are false for it. §0.4 reads them to hide the badge and Delete App. | `settingsCantBeDeleted` |
| Its menu has only Edit Home Screen | `HomeIcon.menu`. | Simulator: one item, opening above the dock as `longpress-menu-dock-safari.png` does. |
| A tap opens the Settings sheet, not a card | `HomeModel.open(Layout.settings)`. Nothing opens in edit mode, as for any icon. | `aTapOnSettingsOpensItsSheet`, `nothingOpensInEditMode` |
| Search finds it | See Search. | `searchOrder` |
