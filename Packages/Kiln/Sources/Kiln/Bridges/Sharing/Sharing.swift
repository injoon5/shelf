//
//  Sharing.swift
//  Bridges: share links, and the app's `Transferable` types (Transferable.swift)
//
//  §1.5 makes `ShareLink` work for a `String`, a `URL` and the app's own
//  `Transferable` values (with `preview:`). Round 2 (§3.2) adds images,
//  `Data`, arrays of items and paste.
//

import SwiftUI

@objc(KilnBridges_Sharing)
final class SharingBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        transferable(r)
        r.view("ShareLink", .sharing, support: .partial,
               notes: "Shares a `String`, a `URL`, or your own `Transferable` type (with `preview: SharePreview(\"Title\")`), with `subject:` and `message:`. Images, `Data` and several items are Round 2's.") { v in
            v.forms(["item:any subject:any? message:any? preview:any?", "_:title item:any subject:any? message:any? preview:any?",
                     "items:any subject:any? message:any? preview:any?", "item:any subject:any? message:any? preview:any? label:content"]) { c in
                shareLink(c)
            }
        }
    }

    @MainActor static func shareLink(_ c: KCall) -> AnyView {
        let title = ControlsBridges.stringTitle(c)
        let subject = c.string("subject").map { Text($0) }
        let message = c.string("message").map { Text($0) }
        let item = c["item"] ?? c["items"].flatMap { $0.asArray?.first } ?? .nilValue
        let preview = KCall.objectValue(c["preview"]) as? KSharePreview
        let label: AnyView? = c.has("label") ? c.content("label") : nil
        @MainActor func link<I: Transferable>(_ i: I) -> AnyView {
            let p = SharePreview<Never, Never>(preview?.title ?? title ?? "Share")
            if let label { return AnyView(ShareLink(item: i, subject: subject, message: message, preview: p) { label }) }
            if let title { return AnyView(ShareLink(title, item: i, subject: subject, message: message, preview: p)) }
            return AnyView(ShareLink(item: i, subject: subject, message: message, preview: p))
        }
        switch item {
        case .string(let s):
            if let label { return AnyView(ShareLink(item: s, subject: subject, message: message) { label }) }
            if let title { return AnyView(ShareLink(title, item: s, subject: subject, message: message)) }
            return AnyView(ShareLink(item: s, subject: subject, message: message))
        case .native(.url(let u)):
            if let label { return AnyView(ShareLink(item: u, subject: subject, message: message) { label }) }
            if let title { return AnyView(ShareLink(title, item: u, subject: subject, message: message)) }
            return AnyView(ShareLink(item: u, subject: subject, message: message))
        default:
            if let transfer = c.interp.proxy(for: item, as: "Transferable") as? KTransferItem { return link(transfer) }
            if let u = item.userType {
                c.interp.report(c.interp.fail("ShareLink: '\(u.name)' isn't Transferable: add `: Transferable` and `static var transferRepresentation`", c.line))
            }
            return AnyView(Label(title ?? "Share", systemImage: "square.and.arrow.up"))
        }
    }
}
