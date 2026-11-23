import Foundation
import os
import QuartzCore

/// Marks on an app's open, for measuring tap to ready (plan §0.8 item 5):
/// press, present, settled, build, built, shown (the app's first frame) and
/// launched (its fade-in done), each with `CACurrentMediaTime()`. Read them with
/// `log stream --level debug --predicate 'subsystem == "dev.ij5.shelf" AND category == "launch"'`.
enum LaunchTiming {
    static let log = Logger(subsystem: "dev.ij5.shelf", category: "launch")

    static func mark(_ what: String, _ slug: String) {
        log.debug("launch \(what, privacy: .public) \(slug, privacy: .public) \(CACurrentMediaTime(), privacy: .public)")
    }
}
