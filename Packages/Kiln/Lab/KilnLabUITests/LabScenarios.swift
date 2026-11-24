//
//  LabScenarios.swift
//  Kiln Lab UI tests: the same scripted session, run against each example
//  compiled natively and interpreted by Kiln. Every step saves a screenshot and
//  the labels on screen, named "<example>|<mode>|<step>", for Lab/report.py to
//  pair up. A missing control is noted, never fatal, so a broken Kiln render
//  still yields a full report.
//

import XCTest

class LabCase: XCTestCase {
    var app: XCUIApplication!
    var example = ""
    var mode = ""
    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        if !notes.isEmpty {
            let a = XCTAttachment(string: notes.joined(separator: "\n"))
            a.name = "\(example)|\(mode)|notes"
            a.lifetime = .keepAlways
            add(a)
        }
        app?.terminate()
    }

    func launch(_ example: String, _ mode: String) {
        self.example = example
        self.mode = mode
        app = XCUIApplication()
        // A fixed seed: shuffles and random picks come out the same natively and in Kiln.
        app.launchArguments = ["-example", example, "-mode", mode, "-seed", "7"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
    }

    func note(_ s: String) { notes.append(s) }

    /// Screenshot plus every label on screen.
    func snap(_ step: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(example)|\(mode)|\(step)"
        shot.lifetime = .keepAlways
        add(shot)
        var labels: [String] = []
        for query in [app.staticTexts, app.buttons, app.textFields, app.switches, app.steppers, app.segmentedControls.buttons] {
            for e in query.allElementsBoundByIndex where e.exists {
                let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { labels.append(label) }
                if let v = e.value as? String, !v.isEmpty, query === app.textFields { labels.append("field: " + v) }
            }
        }
        let t = XCTAttachment(string: labels.joined(separator: "\n"))
        t.name = "\(example)|\(mode)|\(step)|texts"
        t.lifetime = .keepAlways
        add(t)
    }

    func element(_ label: String) -> XCUIElement? {
        for q in [app.buttons, app.staticTexts, app.images, app.cells, app.otherElements] {
            let e = q[label]
            if e.exists { return e }
        }
        let any = app.descendants(matching: .any)[label]
        return any.exists ? any : nil
    }

    @discardableResult
    func tap(_ label: String, wait: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            if let e = element(label), e.isHittable { e.tap(); return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        note("missing: \(label)")
        return false
    }

    @discardableResult
    func type(_ text: String, into placeholder: String) -> Bool {
        let field = app.textFields[placeholder]
        guard field.waitForExistence(timeout: 3) else { note("missing field: \(placeholder)"); return false }
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        return true
    }
}

final class AppScenarios: LabCase {
    // MARK: Habit tracker

    func habit(_ mode: String) {
        launch("HabitTracker", mode)
        snap("1 start")
        tap("Toggle Drink water")
        snap("2 checked off a habit")
        if type("Stretch", into: "e.g. Stretch") { tap("Add") }
        snap("3 added a habit")
        let row = app.cells.containing(.staticText, identifier: "Meditate").firstMatch
        if row.exists {
            row.swipeLeft()
            tap("Delete")
        } else { note("missing row: Meditate") }
        snap("4 deleted a habit")
    }
    func testHabitTrackerNative() { habit("native") }
    func testHabitTrackerKiln() { habit("kiln") }

    // MARK: Tip calculator

    func tip(_ mode: String) {
        launch("TipCalculator", mode)
        snap("1 start")
        tap("20%")
        snap("2 picked 20 percent")
        let stepper = app.steppers.firstMatch
        if stepper.exists { stepper.buttons["Increment"].tap() } else { note("missing stepper") }
        snap("3 added a person")
    }
    func testTipCalculatorNative() { tip("native") }
    func testTipCalculatorKiln() { tip("kiln") }

    // MARK: Focus timer

    func timer(_ mode: String) {
        launch("FocusTimer", mode)
        snap("1 start")
        tap("Start")
        Thread.sleep(forTimeInterval: 3.2)
        tap("Pause")
        snap("2 ran 3 seconds")
        tap("Break")
        snap("3 break mode")
    }
    func testFocusTimerNative() { timer("native") }
    func testFocusTimerKiln() { timer("kiln") }

    // MARK: Memory match

    func memory(_ mode: String) {
        launch("MemoryMatch", mode)
        snap("1 start")
        tap("Card 0")
        tap("Card 1")
        snap("2 flipped two cards")
        Thread.sleep(forTimeInterval: 1.4)
        snap("3 after the pause")
        tap("New Game")
        snap("4 new game")
    }
    func testMemoryMatchNative() { memory("native") }
    func testMemoryMatchKiln() { memory("kiln") }

    // MARK: Expense tracker

    func expense(_ mode: String) {
        launch("ExpenseTracker", mode)
        snap("1 start")
        tap("Add expense")
        snap("2 add sheet")
        type("Coffee", into: "Title")
        type("4.5", into: "Amount")
        snap("3 filled in")
        tap("Save")
        snap("4 saved")
    }
    func testExpenseTrackerNative() { expense("native") }
    func testExpenseTrackerKiln() { expense("kiln") }

    // MARK: Reading list

    func reading(_ mode: String) {
        launch("ReadingList", mode)
        snap("1 start")
        tap("Cosmos")
        snap("2 book detail")
        let finished = app.switches["Finished"]
        if finished.waitForExistence(timeout: 3) {
            finished.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        } else { note("missing switch: Finished") }
        let stepper = app.steppers.firstMatch
        if stepper.exists {
            stepper.buttons["Increment"].tap()
            stepper.buttons["Increment"].tap()
        } else { note("missing stepper") }
        snap("3 finished and rated")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() } else { note("missing back button") }
        snap("4 back in the list")
        tap("Stats")
        snap("5 stats")
        tap("Library")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("weir")
        } else { note("missing search field") }
        snap("6 searched")
    }
    func testReadingListNative() { reading("native") }
    func testReadingListKiln() { reading("kiln") }

    // MARK: Chess

    func chess(_ mode: String) {
        launch("Chess", mode)
        snap("1 start")
        tap("e2")
        snap("2 legal moves")
        // Scholar's mate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#
        for square in ["e4", "e7", "e5", "f1", "c4", "b8", "c6", "d1", "h5", "g8", "f6"] {
            tap(square)
            Thread.sleep(forTimeInterval: 0.4)
        }
        snap("3 queen out")
        tap("h5")
        tap("f7")
        Thread.sleep(forTimeInterval: 0.8)
        snap("4 checkmate")
    }
    func testChessNative() { chess("native") }
    func testChessKiln() { chess("kiln") }

    // MARK: Wave studio (§1.5: custom shapes that animate, Animatable, Transition)

    func wave(_ mode: String) {
        launch("WaveStudio", mode)
        snap("1 start")
        tap("Toggle Weather")
        snap("2 stormy")
        tap("Fill Ring")
        tap("Fill Ring")
        tap("Fill Ring")
        snap("3 ring full")
    }
    func testWaveStudioNative() { wave("native") }
    func testWaveStudioKiln() { wave("kiln") }

    // MARK: Tag cloud (§1.5: a custom Layout, AnyLayout)

    func tags(_ mode: String) {
        launch("TagCloud", mode)
        snap("1 start")
        tap("Add Tag")
        tap("Add Tag")
        snap("2 added tags")
        tap("Switch Layout")
        snap("3 stacked")
    }
    func testTagCloudNative() { tags("native") }
    func testTagCloudKiln() { tags("kiln") }

    // MARK: Card styles (§1.5: ViewModifiers, with state, animatable, as a transition)

    func cards(_ mode: String) {
        launch("CardStyles", mode)
        snap("1 start")
        tap("Tap")
        tap("Tap")
        snap("2 tapped twice")
        tap("Shake")
        tap("Toggle Note")
        snap("3 note hidden")
    }
    func testCardStylesNative() { cards("native") }
    func testCardStylesKiln() { cards("kiln") }

    // MARK: Plant care (Round 1A: controls, layout, lists, navigation)

    func plants(_ mode: String) {
        launch("PlantCare", mode)
        snap("1 start")
        tap("Monstera, 2 days")
        snap("2 pushed a plant")
        tap("Water now")
        // iOS 26's back button is a chevron with no label.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) { back.tap() } else { note("missing: back button") }
        snap("3 watered and back")
        tap("Add")
        snap("4 sheet at medium")
        tap("Add a fern")
        tap("Settings")
        tap("Remind me")
        snap("5 settings, reminders off")
    }
    func testPlantCareNative() { plants("native") }
    func testPlantCareKiln() { plants("kiln") }

    // MARK: Doodle pad (Round 1: gestures, Canvas, focus)

    func doodle(_ mode: String) {
        launch("DoodlePad", mode)
        snap("1 start")
        guard let canvas = element("Doodle canvas") else { note("missing: Doodle canvas"); return }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).doubleTap()
        snap("2 drew and stamped")
        if let label = element("Drag me") {
            let from = label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 90, dy: 0)))
        } else { note("missing: Drag me") }
        snap("3 moved the label")
        tap("Edit title")
        app.typeText("Pond\n")
        snap("4 title submitted, note focused")
        app.typeText("Ducks\n")
        tap("Save")
        snap("5 saved")
    }
    func testDoodlePadNative() { doodle("native") }
    func testDoodlePadKiln() { doodle("kiln") }

    // MARK: Terrain (Round 2 §3.7: Chart3D)

    func terrain(_ mode: String) {
        launch("Terrain", mode)
        snap("1 start")
        tap("Front")
        snap("2 turned to the front")
        tap("Top")
        snap("3 from the top")
        for name in ["Perspective", "Peaks"] {
            let toggle = app.switches[name]
            if toggle.waitForExistence(timeout: 3) {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            } else { note("missing switch: \(name)") }
        }
        snap("4 orthographic, no peaks")
        app.swipeUp()
        let slider = app.sliders.firstMatch
        if slider.waitForExistence(timeout: 3) {
            slider.adjust(toNormalizedSliderPosition: 0.9)
        } else { note("missing slider") }
        snap("5 more ripple")
    }
    func testTerrainNative() { terrain("native") }
    func testTerrainKiln() { terrain("kiln") }

    // MARK: Line feed (Round 2 §3.8: streamed responses)

    func feed(_ mode: String) {
        launch("LineFeed", mode)
        snap("1 start")
        tap("Load")
        Thread.sleep(forTimeInterval: 1)
        snap("2 loaded")
        tap("Load")
        Thread.sleep(forTimeInterval: 1)
        snap("3 loaded again")
    }
    func testLineFeedNative() { feed("native") }
    func testLineFeedKiln() { feed("kiln") }

    // MARK: Trip notes (Round 2A: text parsing, units, haptics, sharing)

    func trip(_ mode: String) {
        launch("TripNotes", mode)
        snap("1 start, the note parsed")
        app.swipeUp()
        tap("Add traveler")
        snap("2 three travelers")
        tap("Walk 2 km more")
        snap("3 walked further")
        app.swipeUp()
        tap("Pack a bag")
        tap("Copy plan")
        snap("4 packed and copied")
    }
    func testTripNotesNative() { trip("native") }
    func testTripNotesKiln() { trip("kiln") }

    // MARK: Ledger (Round 2C: Foundation and the standard library)

    func ledger(_ mode: String) {
        launch("Ledger", mode)
        snap("1 start, March 2026")
        app.swipeUp()
        snap("2 largest first and checks")
        app.swipeUp()
        tap("Add coffee")
        snap("3 coffee added")
        tap("Next month")
        tap("Reshuffle")
        app.swipeDown()
        app.swipeDown()
        snap("4 April, reshuffled")
    }
    func testLedgerNative() { ledger("native") }
    func testLedgerKiln() { ledger("kiln") }

    // MARK: Wayfinder (Round 3B: Core Location's values, sensors' availability)

    func wayfinder(_ mode: String) {
        launch("Wayfinder", mode)
        snap("1 from Apple Park")
        tap("Walk 1 km north")
        tap("Walk 1 km north")
        snap("2 walked 2 km north")
        tap("Ferry Building")
        snap("3 from the Ferry Building")
        app.swipeUp()
        snap("4 a coordinate and this device")
    }
    func testWayfinderNative() { wayfinder("native") }
    func testWayfinderKiln() { wayfinder("kiln") }
}

/// Apple Intelligence's own replies, as Haplo AI receives them. There is no
/// native version (most don't compile), so these record what Kiln shows.
final class ModelReplies: LabCase {
    func reply(_ file: String) {
        launch(file, "kiln")
        snap("1 start")
    }
    func testHabitReply() { reply("habit.md") }
    func testTipReply() { reply("tip.md") }
    func testTimerReply() { reply("timer.md") }
    func testMemoryReply() { reply("memory.md") }
    func testExpenseReply() { reply("expense.md") }
}
