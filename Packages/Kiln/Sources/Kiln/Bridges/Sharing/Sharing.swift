//
//  Sharing.swift
//  Bridges: share links
//

import SwiftUI

@objc(KilnBridges_Sharing)
final class SharingBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.view("ShareLink", .sharing, support: .stub, notes: "Shows its label; sharing isn't wired up yet.") { v in
            v.forms(["item:any subject:any? message:any? preview:any?", "_:title item:any subject:any? message:any? preview:any?",
                     "items:any subject:any? message:any? preview:any?", "item:any subject:any? message:any? preview:any? label:content"]) { c in
                Label(ControlsBridges.stringTitle(c) ?? "Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
