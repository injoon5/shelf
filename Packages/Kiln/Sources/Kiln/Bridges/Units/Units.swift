//
//  Units.swift
//  Bridges: measurements and unit conversion (PLAN.md §3.4)
//
//      let run = Measurement(value: 5, unit: UnitLength.kilometers)
//      run.converted(to: .miles).formatted(.measurement(width: .abbreviated, usage: .road))
//      let smoot = UnitLength(symbol: "smoot", converter: UnitConverterLinear(coefficient: 1.70180))
//
//  A `Measurement` is Foundation's own (`KMeasure` holds a
//  `Measurement<Unit>`), compared by value: `1 km == 1000 m`, `<` converts,
//  `+` and `-` keep the unit when both sides share it, as Swift's do. Units
//  are Foundation's (every class property of every `Dimension` Foundation
//  ships, from `NSUnit.h`), or the app's own made with `UnitConverterLinear`.
//  `.formatted(.measurement(width:usage:numberFormatStyle:))` is
//  `Measurement<UnitType>.FormatStyle` for the unit's own dimension, so usages
//  like `.road` and `.personHeight` pick the locale's units, as compiled.
//
//  Out (PLAN.md): subclassing `Dimension` in the app's code.
//

import SwiftUI

/// Every `Dimension` subclass Foundation ships, and its units (iOS 27.1 SDK's `NSUnit.h`).
enum KUnits {
    static let dimensions: [(String, [String])] = [
        ("UnitAcceleration", ["metersPerSecondSquared", "gravity"]),
        ("UnitAngle", ["degrees", "arcMinutes", "arcSeconds", "radians", "gradians", "revolutions"]),
        ("UnitArea", ["squareMegameters", "squareKilometers", "squareMeters", "squareCentimeters", "squareMillimeters", "squareMicrometers",
                      "squareNanometers", "squareInches", "squareFeet", "squareYards", "squareMiles", "acres", "ares", "hectares"]),
        ("UnitConcentrationMass", ["gramsPerLiter", "milligramsPerDeciliter"]),
        ("UnitDispersion", ["partsPerMillion"]),
        ("UnitDuration", ["hours", "minutes", "seconds", "milliseconds", "microseconds", "nanoseconds", "picoseconds"]),
        ("UnitElectricCharge", ["coulombs", "megaampereHours", "kiloampereHours", "ampereHours", "milliampereHours", "microampereHours"]),
        ("UnitElectricCurrent", ["megaamperes", "kiloamperes", "amperes", "milliamperes", "microamperes"]),
        ("UnitElectricPotentialDifference", ["megavolts", "kilovolts", "volts", "millivolts", "microvolts"]),
        ("UnitElectricResistance", ["megaohms", "kiloohms", "ohms", "milliohms", "microohms"]),
        ("UnitEnergy", ["kilojoules", "joules", "kilocalories", "calories", "kilowattHours"]),
        ("UnitFrequency", ["terahertz", "gigahertz", "megahertz", "kilohertz", "hertz", "millihertz", "microhertz", "nanohertz", "framesPerSecond"]),
        ("UnitFuelEfficiency", ["litersPer100Kilometers", "milesPerImperialGallon", "milesPerGallon"]),
        ("UnitIlluminance", ["lux"]),
        ("UnitInformationStorage", ["bytes", "bits", "nibbles", "yottabytes", "zettabytes", "exabytes", "petabytes", "terabytes", "gigabytes",
                                    "megabytes", "kilobytes", "yottabits", "zettabits", "exabits", "petabits", "terabits", "gigabits", "megabits",
                                    "kilobits", "yobibytes", "zebibytes", "exbibytes", "pebibytes", "tebibytes", "gibibytes", "mebibytes",
                                    "kibibytes", "yobibits", "zebibits", "exbibits", "pebibits", "tebibits", "gibibits", "mebibits", "kibibits"]),
        ("UnitLength", ["megameters", "kilometers", "hectometers", "decameters", "meters", "decimeters", "centimeters", "millimeters",
                        "micrometers", "nanometers", "picometers", "inches", "feet", "yards", "miles", "scandinavianMiles", "lightyears",
                        "nauticalMiles", "fathoms", "furlongs", "astronomicalUnits", "parsecs"]),
        ("UnitMass", ["kilograms", "grams", "decigrams", "centigrams", "milligrams", "micrograms", "nanograms", "picograms", "ounces",
                      "pounds", "stones", "metricTons", "shortTons", "carats", "ouncesTroy", "slugs"]),
        ("UnitPower", ["terawatts", "gigawatts", "megawatts", "kilowatts", "watts", "milliwatts", "microwatts", "nanowatts", "picowatts",
                       "femtowatts", "horsepower"]),
        ("UnitPressure", ["newtonsPerMetersSquared", "gigapascals", "megapascals", "kilopascals", "hectopascals", "inchesOfMercury", "bars",
                          "millibars", "millimetersOfMercury", "poundsForcePerSquareInch"]),
        ("UnitSpeed", ["metersPerSecond", "kilometersPerHour", "milesPerHour", "knots"]),
        ("UnitTemperature", ["kelvin", "celsius", "fahrenheit"]),
        ("UnitVolume", ["megaliters", "kiloliters", "liters", "deciliters", "centiliters", "milliliters", "cubicKilometers", "cubicMeters",
                        "cubicDecimeters", "cubicCentimeters", "cubicMillimeters", "cubicInches", "cubicFeet", "cubicYards", "cubicMiles",
                        "acreFeet", "bushels", "teaspoons", "tablespoons", "fluidOunces", "cups", "pints", "quarts", "gallons",
                        "imperialTeaspoons", "imperialTablespoons", "imperialFluidOunces", "imperialPints", "imperialQuarts",
                        "imperialGallons", "metricCups"]),
    ]
    static let names: [String: [String]] = Dictionary(uniqueKeysWithValues: dimensions)
    /// `kilometers` → `UnitLength`, for a unit written with no type (`unit: .kilometers`).
    static let dimensionOf: [String: String] = {
        var out: [String: String] = [:]
        for (d, units) in dimensions { for u in units where out[u] == nil { out[u] = d } }
        return out
    }()

    /// `UnitLength.kilometers`: Foundation's own unit, by its class property.
    static func unit(_ dimension: String, _ name: String) -> Dimension? {
        guard names[dimension]?.contains(name) == true, let cls = NSClassFromString("NS" + dimension) as? NSObject.Type else { return nil }
        return cls.perform(NSSelectorFromString(selectors[name] ?? name))?.takeUnretainedValue() as? Dimension
    }

    /// `UnitLength(forLocale:)`: the locale's preferred unit (iOS 16).
    static let forLocale: [String: (Locale) -> Dimension] = [
        "UnitLength": { UnitLength(forLocale: $0) }, "UnitMass": { UnitMass(forLocale: $0) },
        "UnitTemperature": { UnitTemperature(forLocale: $0) }, "UnitVolume": { UnitVolume(forLocale: $0) },
        "UnitEnergy": { UnitEnergy(forLocale: $0) }, "UnitPressure": { UnitPressure(forLocale: $0) },
        "UnitSpeed": { UnitSpeed(forLocale: $0) },
    ]

    /// Swift's names that aren't the Objective-C property's (Swift drops the redundant "Mass").
    static let selectors = ["pounds": "poundsMass"]

    static func baseUnit(_ dimension: String) -> Dimension? {
        guard let cls = NSClassFromString("NS" + dimension) as? Dimension.Type else { return nil }
        return cls.baseUnit()
    }

    /// The type an app names a unit by: `UnitLength` for a length, `Unit` for a dimensionless one.
    static func typeName(_ u: Unit) -> String {
        var cls: AnyClass? = type(of: u)
        while let c = cls {
            let name = NSStringFromClass(c)
            if name.hasPrefix("NSUnit"), names[String(name.dropFirst(2))] != nil { return String(name.dropFirst(2)) }
            cls = class_getSuperclass(c)
        }
        return u is Dimension ? "Dimension" : "Unit"
    }

    static func kv(_ u: Unit) -> KV { .native(.boxed(KBoxed(typeName(u), u as NSObject))) }

    static func value(_ v: KV?) -> Unit? {
        if case .native(.boxed(let b))? = v { return b.value.base as? Unit }
        return nil
    }

    /// A unit argument: a unit value, or `.kilometers` resolved in `dimension` (or wherever the name is unique).
    static func resolve(_ v: KV?, in dimension: String?) -> Unit? {
        if let u = value(v) { return u }
        guard case .native(.implicit(let name, let args))? = v, args.isEmpty else { return nil }
        if let dimension, let u = unit(dimension, name) { return u }
        return dimensionOf[name].flatMap { unit($0, name) }
    }
}

/// A `Measurement`, Foundation's own.
struct KMeasure: Hashable, KDescribable {
    var m: Measurement<Unit>

    var dimension: Dimension? { m.unit as? Dimension }
    var dimensionName: String { KUnits.typeName(m.unit) }
    var kv: KV { .native(.boxed(KBoxed("Measurement", self))) }

    /// In its dimension's base unit, for comparing and hashing.
    var baseValue: Double { dimension.map { $0.converter.baseUnitValue(fromValue: m.value) } ?? m.value }

    static func == (a: KMeasure, b: KMeasure) -> Bool {
        guard let da = a.dimension, let db = b.dimension else { return a.m == b.m }
        return KUnits.typeName(da) == KUnits.typeName(db) && a.baseValue == b.baseValue
    }
    func hash(into h: inout Hasher) {
        h.combine(dimension.map { KUnits.typeName($0) } ?? m.unit.symbol)
        h.combine(baseValue)
    }
    func describe(_ interp: KInterpreter) -> String { m.description }

    static func from(_ v: KV?) -> KMeasure? {
        if case .native(.boxed(let b))? = v { return b.get(KMeasure.self) }
        return nil
    }

    func converted(to u: Unit) -> KMeasure? {
        guard let d = dimension, let to = u as? Dimension, KUnits.typeName(d) == KUnits.typeName(to) || type(of: d) == type(of: to) else {
            return u.symbol == m.unit.symbol ? self : nil
        }
        let dm = Measurement<Dimension>(value: m.value, unit: d).converted(to: to)
        return KMeasure(m: Measurement(value: dm.value, unit: dm.unit))
    }

    /// `a + b` and `a - b`: in the shared unit, or in the base unit, as Swift does.
    static func combine(_ a: KMeasure, _ b: KMeasure, _ op: String) -> KMeasure? {
        if a.m.unit.isEqual(b.m.unit) || (a.dimension == nil && a.m.unit.symbol == b.m.unit.symbol) {
            return KMeasure(m: Measurement(value: op == "+" ? a.m.value + b.m.value : a.m.value - b.m.value, unit: a.m.unit))
        }
        guard let da = a.dimension, let db = b.dimension, KUnits.typeName(da) == KUnits.typeName(db),
              let base = KUnits.baseUnit(KUnits.typeName(da)) ?? (da as Dimension?) else { return nil }
        let x = a.baseValue, y = b.baseValue
        return KMeasure(m: Measurement(value: op == "+" ? x + y : x - y, unit: base))
    }
}

/// `.measurement(width:usage:numberFormatStyle:)`, for any dimension.
struct KMeasureStyle: Hashable {
    var width = "abbreviated"
    var usage = "general"
    var number: KFormat?
    var hidesScaleName = false
    var locale: String?
    var kv: KV { .native(.boxed(KBoxed("Measurement.FormatStyle", self))) }

    static func make(_ args: [KV], _ labels: [String?]) -> KMeasureStyle {
        var s = KMeasureStyle()
        for (l, v) in zip(labels, args) {
            switch (l, v) {
            case ("width", .native(.implicit(let n, _))): s.width = n
            case ("usage", .native(.implicit(let n, _))): s.usage = n
            case ("numberFormatStyle", .native(.format(let f))): s.number = f
            case ("hidesScaleName", let b): s.hidesScaleName = b.asBool ?? false
            default: break
            }
        }
        return s
    }

    func format(_ m: KMeasure) -> String {
        let locale = self.locale.map { Locale(identifier: $0) } ?? .autoupdatingCurrent
        var numberStyle: FloatingPointFormatStyle<Double>? = nil
        if let f = number {
            var n = FloatingPointFormatStyle<Double>(locale: locale).grouping(f.grouping ? .automatic : .never)
            if let r = f.fraction { n = n.precision(.fractionLength(r)) }
            numberStyle = n
        }
        guard let d = m.dimension else { return m.m.description }
        let w: Measurement<Dimension>.FormatStyle.UnitWidth = width == "wide" ? .wide : (width == "narrow" ? .narrow : .abbreviated)
        func run<U: Dimension>(_ u: U, _ usage: MeasurementFormatUnitUsage<U>) -> String {
            let uw: Measurement<U>.FormatStyle.UnitWidth = width == "wide" ? .wide : (width == "narrow" ? .narrow : .abbreviated)
            return Measurement(value: m.m.value, unit: u).formatted(Measurement<U>.FormatStyle(width: uw, locale: locale, usage: usage, numberFormatStyle: numberStyle))
        }
        func common<U: Dimension>(_ u: U) -> MeasurementFormatUnitUsage<U> { usage == "asProvided" ? .asProvided : .general }
        switch d {
        case let u as UnitLength:
            let usages: [String: MeasurementFormatUnitUsage<UnitLength>] = ["person": .person, "road": .road, "personHeight": .personHeight,
                "visibility": .visibility, "focalLength": .focalLength, "rainfall": .rainfall, "snowfall": .snowfall]
            return run(u, usages[usage] ?? common(u))
        case let u as UnitTemperature:
            let usage: MeasurementFormatUnitUsage<UnitTemperature> = ["weather": .weather, "person": .person][self.usage] ?? common(u)
            if hidesScaleName {
                let uw: Measurement<UnitTemperature>.FormatStyle.UnitWidth = width == "wide" ? .wide : (width == "narrow" ? .narrow : .abbreviated)
                return Measurement(value: m.m.value, unit: u).formatted(.measurement(width: uw, usage: usage, hidesScaleName: true, numberFormatStyle: numberStyle).locale(locale))
            }
            return run(u, usage)
        case let u as UnitEnergy: return run(u, ["food": .food, "workout": .workout][usage] ?? common(u))
        case let u as UnitMass: return run(u, ["personWeight": .personWeight][usage] ?? common(u))
        case let u as UnitSpeed: return run(u, ["wind": .wind][usage] ?? common(u))
        case let u as UnitPressure: return run(u, ["barometric": .barometric][usage] ?? common(u))
        case let u as UnitVolume: return run(u, ["liquid": .liquid][usage] ?? common(u))
        case let u as UnitAcceleration: return run(u, common(u))
        case let u as UnitAngle: return run(u, common(u))
        case let u as UnitArea: return run(u, common(u))
        case let u as UnitConcentrationMass: return run(u, common(u))
        case let u as UnitDispersion: return run(u, common(u))
        case let u as UnitDuration: return run(u, common(u))
        case let u as UnitElectricCharge: return run(u, common(u))
        case let u as UnitElectricCurrent: return run(u, common(u))
        case let u as UnitElectricPotentialDifference: return run(u, common(u))
        case let u as UnitElectricResistance: return run(u, common(u))
        case let u as UnitFrequency: return run(u, common(u))
        case let u as UnitFuelEfficiency: return run(u, common(u))
        case let u as UnitIlluminance: return run(u, common(u))
        case let u as UnitInformationStorage: return run(u, common(u))
        case let u as UnitPower: return run(u, common(u))
        default:
            return Measurement(value: m.m.value, unit: d).formatted(Measurement<Dimension>.FormatStyle(width: w, locale: locale, usage: .asProvided, numberFormatStyle: numberStyle))
        }
    }
}

/// `MeasurementFormatter`, with its `numberFormatter` the app can set.
final class KMeasurementFormatter {
    let formatter = MeasurementFormatter()
}

@objc(KilnBridges_Units)
final class UnitsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        measurement(r)
        units(r)
        formatting(r)
    }

    /// `Double`, `Locale` and the format styles are other families'.
    override class func extend(into r: KRegistry) {
        KFormatting.valueFormatters["Measurement"] = { v, style, _ in
            guard let m = KMeasure.from(v) else { return nil }
            if case .native(.boxed(let b)) = style, let s = b.get(KMeasureStyle.self) { return s.format(m) }
            if case .native(.implicit("measurement", _)) = style { return KMeasureStyle().format(m) }
            return KMeasureStyle().format(m)
        }
    }

    static func measurement(_ r: KRegistry) {
        r.type("Measurement", .units, support: .full,
               notes: "`Measurement(value:unit:)` in any unit Foundation has, or your own with `UnitConverterLinear`; `converted(to:)`, `+`, `-`, `*`, `/`, comparisons, `.formatted(.measurement(width:usage:))`.") { t in
            for sig in ["value:number unit:any"] {
                t.initializer(sig) { c in
                    guard let v = c.double("value") else { throw c.fail("needs a value") }
                    guard let u = KUnits.resolve(c["unit"], in: nil) else { throw c.fail("needs a unit, such as UnitLength.meters") }
                    return KMeasure(m: Measurement(value: v, unit: u)).kv
                }
            }
            @MainActor func me(_ c: KCall) throws -> KMeasure {
                guard let m = KMeasure.from(c.receiver) else { throw c.noMember() }
                return m
            }
            t.property("value", { c in .double(try me(c).m.value) }, set: { c in
                var m = try me(c)
                m.m.value = c.double(0) ?? 0
                c.mutated = m.kv
            })
            t.property("unit") { c in KUnits.kv(try me(c).m.unit) }
            t.property("description") { c in .string(try me(c).m.description) }
            @MainActor func target(_ c: KCall, _ m: KMeasure) throws -> Unit {
                guard let u = KUnits.resolve(c["to"], in: m.dimensionName) else { throw c.fail("needs a \(m.dimensionName) unit, such as .\(KUnits.names[m.dimensionName]?.first ?? "meters")") }
                return u
            }
            t.method("converted", "to:any") { c in
                let m = try me(c)
                guard let out = m.converted(to: try target(c, m)) else { throw c.fail("can't convert \(m.dimensionName) to \(KUnits.typeName(try target(c, m)))") }
                return out.kv
            }
            t.method("convert", "to:any") { c in
                let m = try me(c)
                guard let out = m.converted(to: try target(c, m)) else { throw c.fail("can't convert \(m.dimensionName) to \(KUnits.typeName(try target(c, m)))") }
                c.mutated = out.kv
                return .void
            }
            t.method("formatted", "") { c in .string(KMeasureStyle().format(try me(c))) }
            t.method("formatted", "_:Measurement.FormatStyle") { c in
                .string(KFormatting.formatted(c.receiver, c[0] ?? .nilValue, c.interp))
            }
            // Arithmetic and comparison, as Foundation's operators.
            t.operator("+") { a, b, line in try arithmetic("+", a, b, line) }
            t.operator("-") { a, b, line in try arithmetic("-", a, b, line) }
            t.operator("*") { a, b, _ in
                if let m = KMeasure.from(a), let k = b.asDouble { return KMeasure(m: Measurement(value: m.m.value * k, unit: m.m.unit)).kv }
                if let m = KMeasure.from(b), let k = a.asDouble { return KMeasure(m: Measurement(value: m.m.value * k, unit: m.m.unit)).kv }
                return nil
            }
            t.operator("/") { a, b, _ in
                if let m = KMeasure.from(a), let k = b.asDouble { return KMeasure(m: Measurement(value: m.m.value / k, unit: m.m.unit)).kv }
                if let m = KMeasure.from(b), let k = a.asDouble { return KMeasure(m: Measurement(value: k / m.m.value, unit: m.m.unit)).kv }
                return nil
            }
            t.operator("<") { a, b, line in
                guard let x = KMeasure.from(a), let y = KMeasure.from(b) else { return nil }
                guard x.dimension.map({ KUnits.typeName($0) }) == y.dimension.map({ KUnits.typeName($0) }) else {
                    throw KERuntimeError(message: "Can't compare \(x.dimensionName) and \(y.dimensionName) measurements", line: line)
                }
                return .bool(x.baseValue < y.baseValue)
            }
        }
        r.type("Measurement.FormatStyle", .units, support: .full,
               notes: "`.measurement(width: .wide | .abbreviated | .narrow, usage: .general | .asProvided | .road | .person | .food | …, numberFormatStyle: .number.precision(…))`.") { t in
            t.implicit { name, args, labels in name == "measurement" ? KMeasureStyle.make(args, labels).kv : nil }
            t.method("locale", "_:any") { c in
                guard case .native(.boxed(let b)) = c.receiver, var s = b.get(KMeasureStyle.self) else { return c.receiver }
                s.locale = FoundationBridges.locale(c[0])?.identifier
                return s.kv
            }
        }
        // `.measurement(…)` wherever a format is written (`Text(m, format:)`, `formatted(_:)`).
        r.addContextFree("measurement") { args, labels, _ in KMeasureStyle.make(args, labels).kv }
    }

    @MainActor static func arithmetic(_ op: String, _ a: KV, _ b: KV, _ line: Int) throws -> KV? {
        guard let x = KMeasure.from(a), let y = KMeasure.from(b) else { return nil }
        guard let out = KMeasure.combine(x, y, op) else {
            throw KERuntimeError(message: "Binary operator '\(op)' can't combine \(x.dimensionName) and \(y.dimensionName) measurements", line: line)
        }
        return out.kv
    }

    static func units(_ r: KRegistry) {
        @MainActor func unitMembers(_ t: KTypeBuilder) {
            t.property("symbol") { c in .string(KUnits.value(c.receiver)?.symbol ?? "") }
            t.property("description") { c in .string(KUnits.value(c.receiver)?.symbol ?? "") }
            t.property("converter") { c in
                guard let d = KUnits.value(c.receiver) as? Dimension else { throw c.noMember() }
                return .native(.object("UnitConverterLinear", KRef(d.converter)))
            }
        }
        for (dimension, names) in KUnits.dimensions {
            r.type(dimension, .units, support: .full) { t in
                t.membersInManifest = true
                for name in names {
                    t.staticProperty(name) { c in
                        guard let u = KUnits.unit(dimension, name) else { throw c.fail("\(dimension).\(name) isn't on this OS") }
                        return KUnits.kv(u)
                    }
                }
                t.staticMethod("baseUnit", "") { c in
                    guard let u = KUnits.baseUnit(dimension) else { throw c.fail("no base unit") }
                    return KUnits.kv(u)
                }
                // The locale's own unit: `UnitTemperature(forLocale: .current)`.
                if let make = KUnits.forLocale[dimension] {
                    t.initializer("forLocale:any usage:any?") { c in KUnits.kv(make(FoundationBridges.locale(c["forLocale"]) ?? .current)) }
                }
                // Your own unit: `UnitLength(symbol: "smoot", converter: UnitConverterLinear(coefficient: 1.70180))`.
                t.initializer("symbol:string converter:any") { c in
                    guard let cls = NSClassFromString("NS" + dimension) as? Dimension.Type,
                          let conv = KCall.objectValue(c["converter"]) as? UnitConverter else { throw c.fail("needs a UnitConverterLinear") }
                    return KUnits.kv(cls.init(symbol: c.string("symbol") ?? "", converter: conv))
                }
                t.implicit { name, args, _ in args.isEmpty ? KUnits.unit(dimension, name).map(KUnits.kv) : nil }
                unitMembers(t)
            }
        }
        r.type("Unit", .units, support: .full, notes: "`Unit(symbol:)`: a unit with no conversions, for counting things.") { t in
            t.initializer("symbol:string") { c in KUnits.kv(Unit(symbol: c.string("symbol") ?? "")) }
            unitMembers(t)
        }
        r.type("Dimension", .units, support: .full) { t in
            t.initializer("symbol:string converter:any") { c in
                guard let conv = KCall.objectValue(c["converter"]) as? UnitConverter else { throw c.fail("needs a UnitConverterLinear") }
                return KUnits.kv(Dimension(symbol: c.string("symbol") ?? "", converter: conv))
            }
            unitMembers(t)
        }
        r.type("UnitConverterLinear", .units, support: .full) { t in
            t.initializer("coefficient:number") { c in .native(.object("UnitConverterLinear", KRef(UnitConverterLinear(coefficient: c.double("coefficient") ?? 1)))) }
            t.initializer("coefficient:number constant:number") { c in
                .native(.object("UnitConverterLinear", KRef(UnitConverterLinear(coefficient: c.double("coefficient") ?? 1, constant: c.double("constant") ?? 0))))
            }
            t.property("coefficient") { c in .double(c.object(UnitConverterLinear.self)?.coefficient ?? 1) }
            t.property("constant") { c in .double(c.object(UnitConverterLinear.self)?.constant ?? 0) }
            t.method("baseUnitValue", "fromValue:number") { c in
                .double(c.object(UnitConverter.self)?.baseUnitValue(fromValue: c.double("fromValue") ?? 0) ?? 0)
            }
            t.method("value", "fromBaseUnitValue:number") { c in
                .double(c.object(UnitConverter.self)?.value(fromBaseUnitValue: c.double("fromBaseUnitValue") ?? 0) ?? 0)
            }
        }
    }

    static func formatting(_ r: KRegistry) {
        r.type("MeasurementFormatter", .units, support: .full,
               notes: "`unitOptions` (`.providedUnit`, `.naturalScale`, `.temperatureWithoutUnit`), `unitStyle`, `locale`, `numberFormatter`; `string(from:)` a measurement or a unit.") { t in
            t.initializer("") { _ in .native(.object("MeasurementFormatter", KRef(KMeasurementFormatter()))) }
            @MainActor func f(_ c: KCall) -> MeasurementFormatter? { c.object(KMeasurementFormatter.self)?.formatter }
            t.property("unitOptions", { c in .array(options(f(c)?.unitOptions ?? [])) }, set: { c in
                var o: MeasurementFormatter.UnitOptions = []
                let values = c.args.first.flatMap { $0.asArray ?? [$0] } ?? []
                for v in values {
                    if case .native(.implicit(let n, _)) = v {
                        if n == "providedUnit" { o.insert(.providedUnit) }
                        if n == "naturalScale" { o.insert(.naturalScale) }
                        if n == "temperatureWithoutUnit" { o.insert(.temperatureWithoutUnit) }
                    }
                }
                f(c)?.unitOptions = o
            })
            t.property("unitStyle", { c in .native(.implicit(style(f(c)?.unitStyle ?? .medium), [])) }, set: { c in
                if case .native(.implicit(let n, _))? = c.args.first { f(c)?.unitStyle = n == "short" ? .short : (n == "long" ? .long : .medium) }
            })
            t.property("locale", { c in FoundationBridges.localeValue(f(c)?.locale ?? .current) }, set: { c in
                if let l = FoundationBridges.locale(c.args.first) { f(c)?.locale = l }
            })
            t.property("numberFormatter", { c in .native(.object("NumberFormatter", KRef(f(c)?.numberFormatter ?? NumberFormatter()))) }, set: { c in
                if let nf = KCall.objectValue(c.args.first) as? NumberFormatter { f(c)?.numberFormatter = nf }
            })
            t.method("string", "from:any") { c in
                guard let fm = f(c) else { return .string("") }
                if let m = KMeasure.from(c["from"]) { return .string(fm.string(from: m.m)) }
                if let u = KUnits.value(c["from"]) { return .string(fm.string(from: u)) }
                throw c.fail("needs a Measurement or a unit")
            }
        }
        @MainActor func options(_ o: MeasurementFormatter.UnitOptions) -> [KV] {
            var out: [KV] = []
            if o.contains(.providedUnit) { out.append(.native(.implicit("providedUnit", []))) }
            if o.contains(.naturalScale) { out.append(.native(.implicit("naturalScale", []))) }
            if o.contains(.temperatureWithoutUnit) { out.append(.native(.implicit("temperatureWithoutUnit", []))) }
            return out
        }
        @MainActor func style(_ s: Formatter.UnitStyle) -> String { s == .short ? "short" : (s == .long ? "long" : "medium") }
    }
}
