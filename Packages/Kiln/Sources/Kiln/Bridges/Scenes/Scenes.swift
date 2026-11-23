//
//  Scenes.swift
//  Bridges: an app's scenes
//
//  A Shelf app is one screen: its `WindowGroup`'s content.
//

import SwiftUI

@objc(KilnBridges_Scenes)
final class ScenesBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.view("WindowGroup", .scenes, support: .partial, notes: "Its content, in the app's card.") { v in
            v.manifestKind = "content"
            v.forms(["content:content", "_:title content:content", "id:string content:content"]) { c in c.r.renderContent(c.a.lastFunction) }
        }
    }
}
