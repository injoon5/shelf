//
//  ControlStyles.swift
//  Bridges: control styles and states
//
//  `.buttonStyle(.borderedProminent)`, `.pickerStyle(.segmented)` … A style
//  is written as an implicit member (`.segmented`) or a type
//  (`SegmentedPickerStyle()`); both arrive as the member's name.
//

import SwiftUI

extension ControlsBridges {
    static func styles(_ r: KRegistry) {
        r.modifier("buttonStyle", .controls, support: .partial) { m in
            m.styles("ButtonStyle", ["borderedProminent", "bordered", "borderless", "plain", "automatic"])
            m.form("_:ButtonStyle") { c, view in
                switch c.symbol(0) {
                case "borderedProminent": view.buttonStyle(.borderedProminent)
                case "bordered": view.buttonStyle(.bordered)
                case "borderless": view.buttonStyle(.borderless)
                case "plain": view.buttonStyle(.plain)
                default: view
                }
            }
        }
        r.modifier("buttonBorderShape", .controls) { m in
            m.form("_:ButtonBorderShape") { c, view in
                switch c.symbol(0) {
                case "capsule": view.buttonBorderShape(.capsule)
                case "circle": view.buttonBorderShape(.circle)
                case "roundedRectangle": view.buttonBorderShape(.roundedRectangle)
                default: view
                }
            }
        }
        r.modifier("pickerStyle", .controls, support: .partial) { m in
            m.styles("PickerStyle", ["segmented", "menu", "inline", "palette", "wheel", "navigationLink", "automatic"])
            m.form("_:PickerStyle") { c, view in
                switch c.symbol(0) {
                case "segmented": AnyView(view.pickerStyle(.segmented))
                case "menu": AnyView(view.pickerStyle(.menu))
                case "inline": AnyView(view.pickerStyle(.inline))
                case "palette": AnyView(view.pickerStyle(.palette))
                #if os(iOS)
                case "wheel": AnyView(view.pickerStyle(.wheel))
                case "navigationLink": AnyView(view.pickerStyle(.navigationLink))
                #endif
                default: view
                }
            }
        }
        r.modifier("toggleStyle", .controls) { m in
            m.styles("ToggleStyle", ["switch", "button", "automatic"])
            m.form("_:ToggleStyle") { c, view in
                if c.symbol(0) == "button" { view.toggleStyle(.button) } else { view.toggleStyle(.switch) }
            }
        }
        r.modifier("textFieldStyle", .controls) { m in
            m.styles("TextFieldStyle", ["roundedBorder", "plain", "automatic"])
            m.form("_:TextFieldStyle") { c, view in
                switch c.symbol(0) {
                case "roundedBorder": AnyView(view.textFieldStyle(.roundedBorder))
                case "plain": AnyView(view.textFieldStyle(.plain))
                default: view
                }
            }
        }
        r.modifier("datePickerStyle", .controls, support: .partial) { m in
            m.styles("DatePickerStyle", ["graphical", "compact", "wheel", "automatic"])
            m.form("_:DatePickerStyle") { c, view in
                switch c.symbol(0) {
                case "graphical": AnyView(view.datePickerStyle(.graphical))
                case "compact": AnyView(view.datePickerStyle(.compact))
                #if os(iOS)
                case "wheel": AnyView(view.datePickerStyle(.wheel))
                #endif
                default: view
                }
            }
        }
        r.modifier("labelStyle", .controls) { m in
            m.styles("LabelStyle", ["iconOnly", "titleOnly", "titleAndIcon", "automatic"])
            m.form("_:LabelStyle") { c, view in
                switch c.symbol(0) {
                case "iconOnly": AnyView(view.labelStyle(.iconOnly))
                case "titleOnly": AnyView(view.labelStyle(.titleOnly))
                case nil: view
                default: AnyView(view.labelStyle(.titleAndIcon))
                }
            }
        }
        r.modifier("progressViewStyle", .controls) { m in
            m.styles("ProgressViewStyle", ["circular", "linear", "automatic"])
            m.form("_:ProgressViewStyle") { c, view in
                if c.symbol(0) == "circular" { view.progressViewStyle(.circular) } else { view.progressViewStyle(.linear) }
            }
        }
        r.modifier("gaugeStyle", .controls, support: .partial) { m in
            m.styles("GaugeStyle", ["accessoryCircular"])
            m.form("_:GaugeStyle") { c, view in
                #if os(iOS)
                if c.symbol(0)?.contains("accessoryCircular") == true { view.gaugeStyle(.accessoryCircular) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("controlSize", .controls) { m in
            m.form("_:ControlSize") { c, view in
                let sizes: [String: ControlSize] = ["mini": .mini, "small": .small, "regular": .regular, "large": .large, "extraLarge": .extraLarge]
                if let n = c.symbol(0) { view.controlSize(sizes[n] ?? .regular) } else { view }
            }
        }
        r.modifier("disabled", .controls) { m in
            m.form("_:bool") { c, view in view.disabled(c.bool(0, default: true)) }
        }
    }
}

extension ControlsBridges {
    /// `.tag(_:)`: how a `Picker` or a `TabView` knows a row.
    static func tags(_ r: KRegistry) {
        r.modifier("tag", .controls, notes: "Read by `Picker` and `TabView`.") { m in
            m.form("_:any includeOptional:bool?") { c, view in view.tag(c[0] ?? .nilValue) }
        }
    }
}
