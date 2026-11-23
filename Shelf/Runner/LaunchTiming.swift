import Foundation
import os
import QuartzCore

/// Marks on an app's open, for measuring tap to ready (plan §0.8 item 5).
enum LaunchTiming {
    static let log = Logger(subsystem: "dev.ij5.shelf", category: "launch")
    static func mark(_ what: String, _ slug: String) {
        log.notice("launch \(what, privacy: .public) \(slug, privacy: .public) \(CACurrentMediaTime(), privacy: .public)")
    }
}
