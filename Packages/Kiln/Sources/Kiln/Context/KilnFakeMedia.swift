//
//  KilnFakeMedia.swift
//  Kiln's run context: a camera and a microphone where there's no hardware
//
//  The simulator has no camera, and a check (`Kiln.validate`) must never
//  open the real microphone. A host (or a test) provides fakes, and the
//  Camera and Audio bridges prefer them (PLAN.md §1.7, §4.3, §4.4):
//
//      context.provide(KilnFakeCamera())       // UIImagePickerController(.camera) shows a fake viewfinder
//      context.provide(KilnFakeMicrophone())   // AVAudioRecorder records a tone, and meters it
//
//  A stub context uses both without being given them. The capability gate
//  still decides: a fake camera an app isn't allowed is refused like a real one.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A camera for the simulator, tests and checks: `UIImagePickerController`
/// with `.camera` shows a viewfinder with a shutter, and taking a photo hands
/// the delegate `photo()`.
@MainActor
public final class KilnFakeCamera {
    #if canImport(UIKit)
    /// The photo each press of the shutter takes.
    public var photo: () -> UIImage
    /// The fake viewfinders showing now: tests call `shoot()` or `cancel()` on one.
    public private(set) var showing: [KilnFakeCameraScreen] = []

    public init(photo: (() -> UIImage)? = nil) {
        self.photo = photo ?? { KilnFakeCamera.testCard() }
    }

    func appeared(_ screen: KilnFakeCameraScreen) { showing.append(screen) }
    func disappeared(_ screen: KilnFakeCameraScreen) { showing.removeAll { $0 === screen } }

    /// A test card: a gradient with the time, 1200 × 900.
    public static func testCard(size: CGSize = CGSize(width: 1200, height: 900)) -> UIImage {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let text = "Kiln camera\n\(stamp)" as NSString
            text.draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.white])
        }
    }
    #else
    public init() {}
    #endif
}

#if canImport(UIKit)
/// One fake viewfinder on screen.
@MainActor
public protocol KilnFakeCameraScreen: AnyObject {
    /// Presses the shutter: the delegate gets the photo.
    func shoot()
    /// Taps Cancel: the delegate hears `imagePickerControllerDidCancel`.
    func cancel()
}
#endif

/// A microphone for checks and tests: `AVAudioRecorder` writes a short tone
/// to its file and meters a level that rises and falls, without touching
/// the real microphone or the audio session.
@MainActor
public final class KilnFakeMicrophone {
    /// The tone's pitch, in hertz.
    public var frequency: Double
    public init(frequency: Double = 440) { self.frequency = frequency }

    /// The level `averagePower(forChannel:)` reads `t` seconds in: −40 to −10 dB.
    func averagePower(at t: TimeInterval) -> Float { Float(-25 + 15 * sin(t * 2 * .pi / 1.5)) }
    func peakPower(at t: TimeInterval) -> Float { min(0, averagePower(at: t) + 6) }

    /// A mono 16-bit WAV of `seconds` of the tone, at 8 kHz.
    func recording(seconds: TimeInterval) -> Data {
        let rate = 8000
        let count = max(1, Int(Double(rate) * seconds))
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
        var bytes: [UInt8] = Array("RIFF".utf8) + le32(36 + count * 2) + Array("WAVE".utf8)
        bytes += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate * 2) + le16(2) + le16(16)
        bytes += Array("data".utf8) + le32(count * 2)
        bytes.reserveCapacity(bytes.count + count * 2)
        for i in 0..<count {
            let v = Int(sin(2 * .pi * frequency * Double(i) / Double(rate)) * 3000)
            bytes += le16(v & 0xFFFF)
        }
        return Data(bytes)
    }
}
