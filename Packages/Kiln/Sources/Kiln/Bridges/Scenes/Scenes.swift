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
        r.modifier("scenePadding", .scenes) { m in
            m.form("_:Edge.Set?") { c, view in view.scenePadding(c.has(0) ? c.edges(0) : .all) }
            m.form("_:any edges:Edge.Set?") { c, view in
                #if os(iOS)
                view.scenePadding(c.symbol(0) == "navigationBar" ? .navigationBar : .minimum, edges: c.has("edges") ? c.edges("edges") : .all)
                #else
                view.scenePadding(.minimum, edges: c.has("edges") ? c.edges("edges") : .all)
                #endif
            }
        }
    }
}
