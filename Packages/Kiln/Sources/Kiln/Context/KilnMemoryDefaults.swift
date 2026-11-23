//
//  KilnMemoryDefaults.swift
//  Kiln's run context: settings that live only as long as a check
//
//  A stub context's `UserDefaults`. A real suite would go through cfprefsd
//  to be made and again to be removed, which a check (run for every reply,
//  every preview) would pay each time; a check's settings never need to
//  outlive it, so they are a dictionary. Every accessor the bridges use is
//  overridden, so nothing reaches the domain behind it.
//

import Foundation

final class KilnMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    private var registered: [String: Any] = [:]

    init() {
        // A domain of its own, never written: every accessor below is overridden.
        super.init(suiteName: nil)!
    }

    private func changed() {
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
    }

    override func object(forKey key: String) -> Any? { values[key] ?? registered[key] }

    override func set(_ value: Any?, forKey key: String) {
        if let value { values[key] = value } else { values[key] = nil }
        changed()
    }

    override func set(_ value: Int, forKey key: String) { set(value as Any, forKey: key) }
    override func set(_ value: Float, forKey key: String) { set(value as Any, forKey: key) }
    override func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
    override func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
    override func set(_ url: URL?, forKey key: String) { set(url?.absoluteString as Any?, forKey: key) }

    override func removeObject(forKey key: String) {
        values[key] = nil
        changed()
    }

    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func url(forKey key: String) -> URL? { string(forKey: key).flatMap(URL.init(string:)) }

    override func integer(forKey key: String) -> Int {
        switch object(forKey: key) {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }

    override func float(forKey key: String) -> Float { Float(double(forKey: key)) }

    override func double(forKey key: String) -> Double {
        switch object(forKey: key) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }

    override func bool(forKey key: String) -> Bool {
        switch object(forKey: key) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["yes", "true", "1"].contains(s.lowercased())
        default: return false
        }
    }

    override func register(defaults: [String: Any]) {
        registered.merge(defaults) { _, new in new }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        registered.merging(values) { _, set in set }
    }

    override func synchronize() -> Bool { true }

    /// The check is over: nothing it set is left.
    func removeAll() {
        values = [:]
        registered = [:]
    }
}
