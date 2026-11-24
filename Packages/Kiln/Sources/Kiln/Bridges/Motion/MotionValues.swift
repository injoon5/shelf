//
//  MotionValues.swift
//  Bridges: Core Motion's values (PLAN.md §4.5)
//
//  What a motion update hands the app. The device's own objects
//  (`CMDeviceMotion`, `CMAttitude`, `CMAccelerometerData`…) can't be made by
//  a fake, so both the device's readings and the fake's become these:
//
//  - `KMotionVector`: `CMAcceleration`, `CMRotationRate`, `CMMagneticField`,
//    `CMQuaternion`, boxed values that print as Swift prints them;
//  - `KRotationMatrix`: `CMRotationMatrix`;
//  - `KAttitude`: `CMAttitude`, with `multiply(byInverseOf:)`;
//  - `KDeviceMotion`, `KSensorData`: the samples.
//

import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif

/// A Core Motion struct of three (or four) doubles.
struct KMotionVector: Hashable, KDescribable {
    let type: String
    var x: Double, y: Double, z: Double
    var w: Double? = nil

    init(_ type: String, _ x: Double, _ y: Double, _ z: Double, w: Double? = nil) {
        self.type = type
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    init(_ type: String, _ v: SIMD3<Double>) { self.init(type, v.x, v.y, v.z) }

    var kv: KV { .native(.boxed(KBoxed(type, self))) }

    func describe(_ interp: KInterpreter) -> String {
        if let w { return "\(type)(x: \(x), y: \(y), z: \(z), w: \(w))" }
        return "\(type)(x: \(x), y: \(y), z: \(z))"
    }

    static func of(_ v: KV?) -> KMotionVector? {
        if case .native(.boxed(let b))? = v { return b.value as? KMotionVector }
        return nil
    }
}

/// `CMRotationMatrix`: m11…m33.
struct KRotationMatrix: Hashable, KDescribable {
    /// Rows.
    var m: [[Double]]

    static let identity = KRotationMatrix(m: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    var kv: KV { .native(.boxed(KBoxed("CMRotationMatrix", self))) }

    subscript(_ r: Int, _ c: Int) -> Double { m[r][c] }

    var transposed: KRotationMatrix { KRotationMatrix(m: (0..<3).map { r in (0..<3).map { c in m[c][r] } }) }

    static func * (a: KRotationMatrix, b: KRotationMatrix) -> KRotationMatrix {
        KRotationMatrix(m: (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + a[r, $1] * b[$1, c] } } })
    }

    func describe(_ interp: KInterpreter) -> String {
        let names = (1...3).flatMap { r in (1...3).map { c in "m\(r)\(c): \(m[r - 1][c - 1])" } }
        return "CMRotationMatrix(" + names.joined(separator: ", ") + ")"
    }

    /// The device's orientation in the reference frame: yaw about z, then
    /// pitch about x, then roll about y (Core Motion's order).
    static func euler(roll: Double, pitch: Double, yaw: Double) -> KRotationMatrix {
        let (cr, sr, cp, sp, cy, sy) = (cos(roll), sin(roll), cos(pitch), sin(pitch), cos(yaw), sin(yaw))
        let rz = KRotationMatrix(m: [[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]])
        let rx = KRotationMatrix(m: [[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
        let ry = KRotationMatrix(m: [[cr, 0, sr], [0, 1, 0], [-sr, 0, cr]])
        return rz * rx * ry
    }

    /// Back to roll, pitch and yaw.
    var euler: (roll: Double, pitch: Double, yaw: Double) {
        let pitch = asin(max(-1, min(1, m[2][1])))
        return (atan2(-m[2][0], m[2][2]), pitch, atan2(-m[0][1], m[1][1]))
    }

    /// Gravity in the device's frame, in g: the reference frame's down.
    var gravity: SIMD3<Double> { SIMD3(-m[2][0], -m[2][1], -m[2][2]) }

    var quaternion: (x: Double, y: Double, z: Double, w: Double) {
        let t = m[0][0] + m[1][1] + m[2][2]
        if t > 0 {
            let s = (t + 1).squareRoot() * 2
            return ((m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, s / 4)
        } else if m[0][0] > m[1][1] && m[0][0] > m[2][2] {
            let s = (1 + m[0][0] - m[1][1] - m[2][2]).squareRoot() * 2
            return (s / 4, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s, (m[2][1] - m[1][2]) / s)
        } else if m[1][1] > m[2][2] {
            let s = (1 + m[1][1] - m[0][0] - m[2][2]).squareRoot() * 2
            return ((m[0][1] + m[1][0]) / s, s / 4, (m[1][2] + m[2][1]) / s, (m[0][2] - m[2][0]) / s)
        } else {
            let s = (1 + m[2][2] - m[0][0] - m[1][1]).squareRoot() * 2
            return ((m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, s / 4, (m[1][0] - m[0][1]) / s)
        }
    }
}

/// `CMAttitude`: a class, because `multiply(byInverseOf:)` changes it in place.
@MainActor
final class KAttitude: KDescribable {
    var matrix: KRotationMatrix
    /// The device's own numbers, when it came from the device: Core Motion's
    /// roll, pitch and yaw, read as they are.
    var device: (roll: Double, pitch: Double, yaw: Double, q: (x: Double, y: Double, z: Double, w: Double))?

    init(matrix: KRotationMatrix) { self.matrix = matrix }

    convenience init(roll: Double, pitch: Double, yaw: Double) {
        self.init(matrix: .euler(roll: roll, pitch: pitch, yaw: yaw))
    }

    var kv: KV { .native(.object("CMAttitude", KRef(self))) }

    var roll: Double { device?.roll ?? matrix.euler.roll }
    var pitch: Double { device?.pitch ?? matrix.euler.pitch }
    var yaw: Double { device?.yaw ?? matrix.euler.yaw }
    var quaternion: KMotionVector {
        let q = device?.q ?? matrix.quaternion
        return KMotionVector("CMQuaternion", q.x, q.y, q.z, w: q.w)
    }

    /// Relative to `reference`: what `multiply(byInverseOf:)` leaves.
    func multiply(byInverseOf reference: KAttitude) {
        matrix = reference.matrix.transposed * matrix
        device = nil
    }

    func copy() -> KAttitude {
        let a = KAttitude(matrix: matrix)
        a.device = device
        return a
    }

    func describe(_ interp: KInterpreter) -> String {
        String(format: "CMAttitude Pitch: %.6f, Roll: %.6f, Yaw: %.6f", pitch * 180 / .pi, roll * 180 / .pi, yaw * 180 / .pi)
    }
}

/// `CMDeviceMotion`.
@MainActor
final class KDeviceMotion {
    let attitude: KAttitude
    let rotationRate: KMotionVector
    let gravity: KMotionVector
    let userAcceleration: KMotionVector
    let magneticField: KMotionVector
    /// -1 to 2: uncalibrated to high.
    let magneticAccuracy: Int
    /// Degrees from north, or -1 when the reference frame has no north.
    let heading: Double
    let timestamp: TimeInterval
    /// "default", "headphoneLeft", "headphoneRight".
    let sensorLocation: String

    init(attitude: KAttitude, rotationRate: KMotionVector, gravity: KMotionVector, userAcceleration: KMotionVector,
         magneticField: KMotionVector, magneticAccuracy: Int, heading: Double, timestamp: TimeInterval, sensorLocation: String) {
        self.attitude = attitude
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.magneticField = magneticField
        self.magneticAccuracy = magneticAccuracy
        self.heading = heading
        self.timestamp = timestamp
        self.sensorLocation = sensorLocation
    }

    var kv: KV { .native(.object("CMDeviceMotion", KRef(self))) }

    /// A fake's reading as Core Motion would report it in `frame`.
    static func fake(_ r: KilnFakeMotion.Reading, frame: String, at timestamp: TimeInterval, sensorLocation: String = "default") -> KDeviceMotion {
        let attitude = KAttitude(roll: r.roll, pitch: r.pitch, yaw: r.yaw)
        let north = frame == "xMagneticNorthZVertical" || frame == "xTrueNorthZVertical"
        var heading = -1.0
        if north {
            // The device's top (+y) measured clockwise from north.
            heading = (-r.yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
            if heading < 0 { heading += 360 }
        }
        return KDeviceMotion(attitude: attitude, rotationRate: KMotionVector("CMRotationRate", r.rotationRate),
                             gravity: KMotionVector("CMAcceleration", attitude.matrix.gravity),
                             userAcceleration: KMotionVector("CMAcceleration", r.userAcceleration),
                             magneticField: KMotionVector("CMMagneticField", north ? r.magneticField : .zero),
                             magneticAccuracy: north ? 2 : -1, heading: heading, timestamp: timestamp, sensorLocation: sensorLocation)
    }

    #if os(iOS) || os(watchOS) || os(visionOS)
    static func device(_ m: CMDeviceMotion) -> KDeviceMotion {
        let a = m.attitude
        let r = a.rotationMatrix
        let attitude = KAttitude(matrix: KRotationMatrix(m: [[r.m11, r.m12, r.m13], [r.m21, r.m22, r.m23], [r.m31, r.m32, r.m33]]))
        attitude.device = (a.roll, a.pitch, a.yaw, (a.quaternion.x, a.quaternion.y, a.quaternion.z, a.quaternion.w))
        let location: String
        switch m.sensorLocation {
        case .headphoneLeft: location = "headphoneLeft"
        case .headphoneRight: location = "headphoneRight"
        default: location = "default"
        }
        return KDeviceMotion(attitude: attitude,
                             rotationRate: KMotionVector("CMRotationRate", m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                             gravity: KMotionVector("CMAcceleration", m.gravity.x, m.gravity.y, m.gravity.z),
                             userAcceleration: KMotionVector("CMAcceleration", m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z),
                             magneticField: KMotionVector("CMMagneticField", m.magneticField.field.x, m.magneticField.field.y, m.magneticField.field.z),
                             magneticAccuracy: Int(m.magneticField.accuracy.rawValue), heading: m.heading, timestamp: m.timestamp,
                             sensorLocation: location)
    }
    #endif
}

/// `CMAccelerometerData`, `CMGyroData`, `CMMagnetometerData`: one raw
/// sensor's reading.
@MainActor
final class KSensorData {
    /// The bridge's type name: `CMAccelerometerData`…
    let type: String
    let vector: KMotionVector
    let timestamp: TimeInterval

    init(type: String, vector: KMotionVector, timestamp: TimeInterval) {
        self.type = type
        self.vector = vector
        self.timestamp = timestamp
    }

    var kv: KV { .native(.object(type, KRef(self))) }
}

/// Core Motion's errors, as the device gives them.
enum KMotionErrors {
    /// `CMErrorMotionActivityNotAuthorized`: what the pedometer, the activity
    /// manager, the altimeter and headphone motion give an app that isn't allowed.
    static let notAuthorized = 105
    /// `CMErrorMotionActivityNotAvailable`.
    static let notAvailable = 104

    @MainActor static func error(_ code: Int) -> KV {
        let message: String
        switch code {
        case notAuthorized: message = "The operation couldn’t be completed. (CMErrorDomain error 105.)"
        case notAvailable: message = "The operation couldn’t be completed. (CMErrorDomain error 104.)"
        default: message = "The operation couldn’t be completed. (CMErrorDomain error \(code).)"
        }
        return .native(.object("Error", KRef(NSError(domain: "CMErrorDomain", code: code, userInfo: [NSLocalizedDescriptionKey: message]))))
    }
}

extension MotionBridges {
    static func values(_ r: KRegistry) {
        @MainActor func vec(_ c: KCall) -> KMotionVector? { KMotionVector.of(c.receiver) }
        for (name, fields) in [("CMAcceleration", ["x", "y", "z"]), ("CMRotationRate", ["x", "y", "z"]),
                               ("CMMagneticField", ["x", "y", "z"]), ("CMQuaternion", ["x", "y", "z", "w"])] {
            r.type(name, .motion, support: .full) { t in
                let sig = fields.map { "\($0):number" }.joined(separator: " ")
                t.initializer(sig) { c in
                    let v = KMotionVector(name, c.double("x") ?? 0, c.double("y") ?? 0, c.double("z") ?? 0,
                                          w: fields.count == 4 ? c.double("w") ?? 0 : nil)
                    return v.kv
                }
                t.initializer("") { _ in KMotionVector(name, 0, 0, 0, w: fields.count == 4 ? 0 : nil).kv }
                for f in fields {
                    t.property(f, { c in
                        guard let v = vec(c) else { return .double(0) }
                        switch f { case "x": return .double(v.x); case "y": return .double(v.y); case "z": return .double(v.z)
                        default: return .double(v.w ?? 0) }
                    }, set: { c in
                        guard var v = vec(c), let n = c.args.first?.asDouble else { return }
                        switch f { case "x": v.x = n; case "y": v.y = n; case "z": v.z = n; default: v.w = n }
                        c.mutated = v.kv
                    })
                }
            }
        }
        r.type("CMRotationMatrix", .motion, support: .full) { t in
            t.initializer("") { _ in KRotationMatrix.identity.kv }
            for row in 1...3 {
                for col in 1...3 {
                    t.property("m\(row)\(col)") { c in
                        guard case .native(.boxed(let b)) = c.receiver, let m = b.value as? KRotationMatrix else { return .double(0) }
                        return .double(m[row - 1, col - 1])
                    }
                }
            }
        }
        r.type("CMCalibratedMagneticField", .motion, support: .full) { t in
            t.property("field") { c in
                guard case .tuple(let parts, _) = c.receiver, let f = parts.first else { return .nilValue }
                return f
            }
            t.property("accuracy") { c in
                guard case .tuple(let parts, _) = c.receiver, parts.count > 1 else { return .nilValue }
                return parts[1]
            }
        }

        r.type("CMAttitude", .motion, support: .full,
               notes: "`roll`, `pitch`, `yaw` (radians), `quaternion`, `rotationMatrix`; `multiply(byInverseOf:)` for an attitude relative to one you kept.") { t in
            @MainActor func me(_ c: KCall) -> KAttitude? { c.object(KAttitude.self) }
            t.property("roll") { c in .double(me(c)?.roll ?? 0) }
            t.property("pitch") { c in .double(me(c)?.pitch ?? 0) }
            t.property("yaw") { c in .double(me(c)?.yaw ?? 0) }
            t.property("quaternion") { c in (me(c)?.quaternion ?? KMotionVector("CMQuaternion", 0, 0, 0, w: 1)).kv }
            t.property("rotationMatrix") { c in (me(c)?.matrix ?? .identity).kv }
            t.method("multiply", "byInverseOf:CMAttitude") { c in
                guard let a = me(c), let ref = c["byInverseOf"].flatMap({ v -> KAttitude? in
                    if case .native(.object(_, let o)) = v { return o.value as? KAttitude }; return nil
                }) else { throw c.fail("needs a CMAttitude") }
                a.multiply(byInverseOf: ref)
                return .void
            }
            t.method("copy", "") { c in me(c)?.copy().kv ?? .nilValue }
        }

        r.type("CMDeviceMotion", .motion, support: .full,
               notes: "`attitude`, `rotationRate`, `gravity`, `userAcceleration`, `magneticField`, `heading` (with a north reference frame), `timestamp`.") { t in
            @MainActor func me(_ c: KCall) -> KDeviceMotion? { c.object(KDeviceMotion.self) }
            t.property("attitude") { c in me(c)?.attitude.kv ?? .nilValue }
            t.property("rotationRate") { c in me(c)?.rotationRate.kv ?? .nilValue }
            t.property("gravity") { c in me(c)?.gravity.kv ?? .nilValue }
            t.property("userAcceleration") { c in me(c)?.userAcceleration.kv ?? .nilValue }
            t.property("magneticField") { c in
                guard let m = me(c) else { return .nilValue }
                return .tuple([m.magneticField.kv, .native(.implicit(accuracyName(m.magneticAccuracy), []))], ["field", "accuracy"])
            }
            t.property("heading") { c in .double(me(c)?.heading ?? -1) }
            t.property("timestamp") { c in .double(me(c)?.timestamp ?? 0) }
            t.property("sensorLocation") { c in .native(.implicit(me(c)?.sensorLocation ?? "default", [])) }
        }
        r.alias("CMCalibratedMagneticField.Accuracy", to: "CMMagneticFieldCalibrationAccuracy")

        for (type, property) in [("CMAccelerometerData", "acceleration"), ("CMGyroData", "rotationRate"), ("CMMagnetometerData", "magneticField")] {
            r.type(type, .motion, support: .full) { t in
                t.property(property) { c in c.object(KSensorData.self)?.vector.kv ?? .nilValue }
                t.property("timestamp") { c in .double(c.object(KSensorData.self)?.timestamp ?? 0) }
            }
        }

        // Enum-like types, compared with `==` and `switch`.
        symbols(r, "CMAttitudeReferenceFrame", ["xArbitraryZVertical", "xArbitraryCorrectedZVertical", "xMagneticNorthZVertical", "xTrueNorthZVertical"])
        symbols(r, "CMMagneticFieldCalibrationAccuracy", ["uncalibrated", "low", "medium", "high"])
        symbols(r, "CMDeviceMotion.SensorLocation", ["default", "headphoneLeft", "headphoneRight"])
        symbols(r, "CMAuthorizationStatus", ["notDetermined", "restricted", "denied", "authorized"])
        symbols(r, "CMMotionActivityConfidence", ["low", "medium", "high"])
        symbols(r, "CMPedometerEventType", ["pause", "resume"])
    }

    /// An enum-like type whose cases are symbols.
    static func symbols(_ r: KRegistry, _ name: String, _ cases: [String]) {
        r.type(name, .motion, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: cases.map { ($0, KV.native(.implicit($0, []))) }))
            t.property("rawValue") { c in
                if case .native(.implicit(let n, _)) = c.receiver, let i = cases.firstIndex(of: n) {
                    return .int(name == "CMMagneticFieldCalibrationAccuracy" ? i - 1 : (name == "CMAttitudeReferenceFrame" ? 1 << i : i))
                }
                return .int(0)
            }
        }
    }

    static func accuracyName(_ raw: Int) -> String {
        switch raw {
        case 0: return "low"
        case 1: return "medium"
        case 2: return "high"
        default: return "uncalibrated"
        }
    }
}
