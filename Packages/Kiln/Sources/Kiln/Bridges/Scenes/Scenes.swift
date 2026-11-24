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
            // `makeContent:` and `lazyContent:` (iOS 17.5) are SwiftUI's other names for the content;
            // the title and id name a window, and a Kiln app has the one.
            v.forms(["content:content", "_:title content:content", "id:string content:content", "_:title id:string content:content",
                     "makeContent:content", "_:title makeContent:content", "id:string makeContent:content", "_:title id:string makeContent:content",
                     "id:string? title:any? lazyContent:content"]) { c in c.r.renderContent(c.a.lastFunction) }
        }
        r.modifier("scenePadding", .scenes) { m in
            m.form("_:Edge.Set?") { c, view in view.scenePadding(c.has(0) ? c.edges(0) : .all) }
            m.form("_:any edges:Edge.Set?") { c, view in
                // `.navigationBar` is watchOS's; iOS has `.minimum`.
                view.scenePadding(.minimum, edges: c.has("edges") ? c.edges("edges") : .all)
            }
        }
    }
}
