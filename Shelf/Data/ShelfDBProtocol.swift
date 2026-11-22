import Foundation

/// Answers the private `db://` scheme from the open app's `DBSession`, without
/// touching the network (plan §8.4).
///
/// CONTRACT — signatures are fixed; bodies belong to the Data package.
final class ShelfDBProtocol: URLProtocol, @unchecked Sendable {
    /// Routes `db://` requests on `URLSession.shared` to `session` until
    /// `deactivate`. Shelf runs one app at a time, so the slug is never in the URL.
    static func activate(_ session: DBSession) {}

    /// Stops answering for `session`. A newer session that has since been
    /// activated is left alone.
    static func deactivate(_ session: DBSession) {}
}
