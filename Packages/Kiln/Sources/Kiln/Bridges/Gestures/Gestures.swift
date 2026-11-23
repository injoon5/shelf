//
//  Gestures.swift
//  Bridges: taps, long presses and hit testing
//
//  Gesture values (`DragGesture` and the rest) are Round 1's; `.gesture` and
//  its kin are accepted so code that uses them runs, without the gesture.
//

import SwiftUI

@objc(KilnBridges_Gestures)
final class GesturesBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.modifier("onTapGesture", .gestures) { m in
            m.forms(["count:number? perform:action", "count:number? coordinateSpace:any? perform:action"]) { c, view in
                view.onTapGesture(count: c.int("count") ?? 1, perform: c.action("perform"))
            }
        }
        r.modifier("onLongPressGesture", .gestures) { m in
            m.forms(["minimumDuration:number? maximumDistance:number? perform:action onPressingChanged:closure?",
                     "minimumDuration:number? maximumDistance:number? pressing:closure? perform:action"]) { c, view in
                view.onLongPressGesture(perform: c.action("perform"))
            }
        }
        for name in ["gesture", "simultaneousGesture", "highPriorityGesture"] {
            r.modifier(name, .gestures, support: .stub, notes: "Accepted, but no gesture runs yet.") { m in m.stub(["_:any including:any?", "_:any isEnabled:bool"]) }
        }
        r.modifier("allowsHitTesting", .gestures) { m in
            m.form("_:bool") { c, view in view.allowsHitTesting(c.bool(0, default: true)) }
        }
        r.modifier("contentShape", .gestures) { m in
            m.forms(["_:any eoFill:bool?", "_:any _:any eoFill:bool?"]) { c, view in
                if let shape = DrawingBridges.shapeArg(c.labels.count > 1 && (c.labels[1] ?? nil) == nil ? c[1] : c[0], c.r) {
                    view.contentShape(shape)
                } else {
                    view.contentShape(Rectangle())
                }
            }
        }
        r.modifier("onHover", .gestures, support: .stub) { m in m.stub(["perform:action"]) }
    }
}
