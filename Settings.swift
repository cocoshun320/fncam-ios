import Foundation

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private init() {}

    var host: String {
        get { d.string(forKey: "host") ?? "" }
        set { d.set(newValue, forKey: "host") }
    }
    var port: Int {
        get { let v = d.integer(forKey: "port"); return v == 0 ? 21 : v }
        set { d.set(newValue, forKey: "port") }
    }
    var user: String {
        get { d.string(forKey: "user") ?? "" }
        set { d.set(newValue, forKey: "user") }
    }
    var pass: String {
        get { d.string(forKey: "pass") ?? "" }
        set { d.set(newValue, forKey: "pass") }
    }
    var dir: String {
        get { d.string(forKey: "dir") ?? "/" }
        set { d.set(newValue, forKey: "dir") }
    }
    var ftps: Bool {
        get { d.bool(forKey: "ftps") }
        set { d.set(newValue, forKey: "ftps") }
    }
    var wifiOnly: Bool {
        get { d.bool(forKey: "wifi") }
        set { d.set(newValue, forKey: "wifi") }
    }
    var deleteAfter: Bool {
        get { d.object(forKey: "del") == nil ? true : d.bool(forKey: "del") }
        set { d.set(newValue, forKey: "del") }
    }
    var autoUpload: Bool {
        get { d.object(forKey: "auto") == nil ? true : d.bool(forKey: "auto") }
        set { d.set(newValue, forKey: "auto") }
    }
    var album: String {
        get {
            let s = d.string(forKey: "album") ?? ""
            return s.isEmpty ? "影传相机" : s
        }
        set { d.set(newValue, forKey: "album") }
    }
    var segmentSec: Int {
        get { d.integer(forKey: "segsec") }
        set { d.set(newValue, forKey: "segsec") }
    }
    var maxTotalMin: Int {
        get { d.integer(forKey: "maxmin") }
        set { d.set(newValue, forKey: "maxmin") }
    }
    var dirLevels: [String] {
        get {
            if let a = d.array(forKey: "dirlevels") as? [String] { return a }
            return ["{date}", "{type}"]
        }
        set { d.set(newValue, forKey: "dirlevels") }
    }
    var dirPattern: String { dirLevels.joined(separator: "/") }

    static func stamp(_ prefix: String, _ ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return prefix + "_" + f.string(from: Date()) + ext
    }
}