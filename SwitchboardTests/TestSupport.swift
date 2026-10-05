import Foundation
import XCTest

/// A `UserDefaults` that keeps everything in memory.
///
/// A suite made with `UserDefaults(suiteName:)` is written to
/// ~/Library/Preferences by cfprefsd, and `removePersistentDomain` empties the
/// plist without deleting it. Every test that made a suite left one file
/// behind for good.
final class InMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        // The standard domain is never read or written: every accessor below is overridden.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }

    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        values[defaultName] = nil
    }

    // The typed accessors are separate Objective-C methods. Each is routed
    // here explicitly so none can fall through to the real domain.
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Float, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ url: URL?, forKey defaultName: String) { values[defaultName] = url }

    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func array(forKey defaultName: String) -> [Any]? { values[defaultName] as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { values[defaultName] as? [String: Any] }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func stringArray(forKey defaultName: String) -> [String]? { values[defaultName] as? [String] }
    override func url(forKey defaultName: String) -> URL? { values[defaultName] as? URL }

    override func bool(forKey defaultName: String) -> Bool {
        switch values[defaultName] {
        case let number as NSNumber: return number.boolValue
        case let text as NSString: return text.boolValue
        default: return false
        }
    }

    override func integer(forKey defaultName: String) -> Int {
        switch values[defaultName] {
        case let number as NSNumber: return number.intValue
        case let text as NSString: return text.integerValue
        default: return 0
        }
    }

    override func float(forKey defaultName: String) -> Float { Float(double(forKey: defaultName)) }

    override func double(forKey defaultName: String) -> Double {
        switch values[defaultName] {
        case let number as NSNumber: return number.doubleValue
        case let text as NSString: return text.doubleValue
        default: return 0
        }
    }

    override func dictionaryRepresentation() -> [String: Any] { values }

    override func synchronize() -> Bool { true }
}

/// Throwaway CFPreferences domains, for code that writes real preference
/// domains and so cannot take an `InMemoryDefaults`.
enum ScratchPreferenceDomain {
    static let prefix = "com.switchboard.tests."

    static func make(_ purpose: String) -> String {
        LeftoverSweep.shared.register()
        return "\(prefix)\(purpose).\(UUID().uuidString)"
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    /// Deletes the plist of every scratch domain. Nothing in macOS removes
    /// the file of a domain that has been emptied.
    static func removeLeftoverFiles() {
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            for name in names where name.hasPrefix(prefix) && name.hasSuffix(".plist") {
                try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        } catch {
            // Nothing a test can do about it; say so, so the files are not a mystery later.
            print("Scratch preference files were left in \(folder.path): \(error.localizedDescription)")
        }
    }
}

/// Clears scratch domains left by an earlier run before the first one is
/// made, and this run's once the test process has gone.
private final class LeftoverSweep: NSObject, XCTestObservation {
    static let shared = LeftoverSweep()
    /// A ceiling on the wait below, so a test process that never exits
    /// cannot leave a shell polling for good.
    private static let maximumWaitSeconds = 120
    private var isRegistered = false

    func register() {
        guard !isRegistered else { return }
        isRegistered = true
        ScratchPreferenceDomain.removeLeftoverFiles()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    /// cfprefsd writes a changed domain to disk about seven seconds after the
    /// change, or when the process that changed it exits, whichever comes
    /// first. A file deleted before that write reappears. So a shell waits for
    /// this process to go and removes the files after the write has landed,
    /// then once more in case a write was still on its way.
    func testBundleDidFinish(_ testBundle: Bundle) {
        let files = "\"\(ScratchPreferenceDomain.folder.path)/\"\(ScratchPreferenceDomain.prefix)*.plist"
        let waitThenRemove = """
        polls=0
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null && [ $polls -lt \(Self.maximumWaitSeconds * 5) ]; do
          sleep 0.2
          polls=$((polls + 1))
        done
        sleep 3
        rm -f \(files)
        sleep 7
        rm -f \(files)
        """
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "(\(waitThenRemove)) >/dev/null 2>&1 &"]
        do {
            try cleanup.run()
        } catch {
            // The next run's first scratch domain clears them instead.
            print("Scratch preference cleanup could not start: \(error.localizedDescription)")
        }
    }
}

final class InMemoryDefaultsTests: XCTestCase {
    /// If any accessor fell through to the real domain, tests would write to
    /// the preferences of whatever runs them.
    func testEveryAccessorStaysInMemory() {
        let defaults = InMemoryDefaults()
        let key = "InMemoryDefaultsTests.\(UUID().uuidString)"
        let writes: [(String, () -> Void)] = [
            ("object", { defaults.set("text" as Any, forKey: key) }),
            ("bool", { defaults.set(true, forKey: key) }),
            ("int", { defaults.set(7, forKey: key) }),
            ("float", { defaults.set(Float(1.5), forKey: key) }),
            ("double", { defaults.set(2.5, forKey: key) }),
            ("url", { defaults.set(URL(fileURLWithPath: "/tmp"), forKey: key) }),
            ("data", { defaults.set(Data([1, 2]), forKey: key) }),
            ("strings", { defaults.set(["a", "b"], forKey: key) }),
            ("dictionary", { defaults.set(["a": "b"], forKey: key) })
        ]
        for (name, write) in writes {
            write()
            XCTAssertNotNil(defaults.object(forKey: key), name)
            XCTAssertNil(UserDefaults.standard.object(forKey: key), "\(name) reached the real domain")
        }
        defaults.removeObject(forKey: key)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testTypedReadsMatchWhatWasWritten() {
        let defaults = InMemoryDefaults()
        defaults.set(true, forKey: "flag")
        defaults.set(7, forKey: "count")
        defaults.set(2.5, forKey: "ratio")
        defaults.set("text", forKey: "name")
        defaults.set(Data([1, 2]), forKey: "bytes")
        defaults.set(["a", "b"], forKey: "list")
        defaults.set(["a": "b"], forKey: "map")

        XCTAssertTrue(defaults.bool(forKey: "flag"))
        XCTAssertEqual(defaults.integer(forKey: "count"), 7)
        XCTAssertEqual(defaults.double(forKey: "ratio"), 2.5)
        XCTAssertEqual(defaults.string(forKey: "name"), "text")
        XCTAssertEqual(defaults.data(forKey: "bytes"), Data([1, 2]))
        XCTAssertEqual(defaults.stringArray(forKey: "list"), ["a", "b"])
        XCTAssertEqual(defaults.dictionary(forKey: "map") as? [String: String], ["a": "b"])
        XCTAssertFalse(defaults.bool(forKey: "missing"))
        XCTAssertNil(defaults.string(forKey: "missing"))
    }
}
