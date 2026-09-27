import Combine
import Foundation
import OSLog

/// A release number such as 1.1.4, compared part by part as integers so 1.10
/// sorts after 1.9. Missing parts count as zero, which makes 1.2 equal 1.2.0.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    /// Accepts a bundle version ("1.1.4") or a release tag ("v1.1.4"). Anything
    /// with a suffix, such as "1.2.0-beta", is refused rather than guessed at.
    init?(_ text: String) {
        let number = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let pieces = number.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parsed: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty,
                  piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(piece) else { return nil }
            parsed.append(value)
        }
        parts = parsed
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { order(lhs, rhs) == 0 }
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { order(lhs, rhs) < 0 }

    private static func order(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

enum UpdateCheckError: Error, CustomStringConvertible {
    case notHTTP
    case status(Int)
    case unreadableTag(String)
    case unreadableInstalledVersion

    var description: String {
        switch self {
        case .notHTTP: return "response was not HTTP"
        case .status(let code): return "GitHub answered with status \(code)"
        case .unreadableTag(let tag): return "latest release tag \"\(tag)\" is not a version number"
        case .unreadableInstalledVersion: return "the installed version is not a version number"
        }
    }
}

protocol ReleaseFeed: Sendable {
    func latestVersion() async throws -> AppVersion
}

/// Reads the newest published release from GitHub. The latest-release endpoint
/// already leaves out drafts and prereleases.
struct GitHubReleaseFeed: ReleaseFeed {
    static let latestReleaseEndpoint = URL(string: "https://api.github.com/repos/Mehul72/switchboard/releases/latest")!
    // GitHub usually answers in well under a second. These bound a stalled
    // connection, so a check never hangs on a network that accepts and stays silent.
    static let requestTimeoutSeconds: TimeInterval = 10
    static let totalTimeoutSeconds: TimeInterval = 20

    private let session: URLSession
    private let endpoint: URL
    private let userAgent: String

    init(userAgent: String,
         session: URLSession = GitHubReleaseFeed.makeSession(),
         endpoint: URL = GitHubReleaseFeed.latestReleaseEndpoint) {
        self.userAgent = userAgent
        self.session = session
        self.endpoint = endpoint
    }

    static func makeSession(requestTimeoutSeconds: TimeInterval = requestTimeoutSeconds,
                            totalTimeoutSeconds: TimeInterval = totalTimeoutSeconds) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = totalTimeoutSeconds
        // Offline should fail now and be retried by the next scheduled tick,
        // not hold a request open until the network comes back.
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func latestVersion() async throws -> AppVersion {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects API requests that carry no User-Agent.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.notHTTP }
        guard http.statusCode == 200 else { throw UpdateCheckError.status(http.statusCode) }
        return try Self.version(inLatestRelease: body)
    }

    static func version(inLatestRelease body: Data) throws -> AppVersion {
        let release = try JSONDecoder().decode(LatestRelease.self, from: body)
        guard let version = AppVersion(release.tagName) else {
            throw UpdateCheckError.unreadableTag(release.tagName)
        }
        return version
    }

    private struct LatestRelease: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}

/// Asks GitHub whether a newer Switchboard has been released. It never
/// downloads anything; people update from the release page themselves.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Report: Equatable {
        case upToDate(installed: AppVersion)
        case available(latest: AppVersion, installed: AppVersion)
        case failed
    }

    static let releasePage = URL(string: "https://github.com/Mehul72/switchboard/releases/latest")!
    static let automaticKey = "UpdateChecksAutomatically"
    static let lastSuccessKey = "UpdateLastSuccessfulCheck"
    static let latestKnownKey = "UpdateLatestKnownVersion"
    static let checkIntervalSeconds: TimeInterval = 24 * 60 * 60
    // A check missed while offline or asleep runs soon after, and a network
    // that keeps failing costs one request an hour, well inside GitHub's limit.
    static let tickIntervalSeconds: TimeInterval = 60 * 60
    // Keeps the first request clear of login, when the network may not be up yet.
    static let launchDelaySeconds: TimeInterval = 60

    @Published private(set) var availableVersion: AppVersion?
    @Published private(set) var isChecking = false
    @Published var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Self.automaticKey) }
    }

    var onReport: ((Report) -> Void)?
    let installedVersion: AppVersion?

    private let feed: ReleaseFeed
    private let defaults: UserDefaults
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "updates")
    private var inFlight: Task<Void, Never>?
    private var someoneIsWaiting = false
    private var timer: Timer?

    init(installedVersion: AppVersion?,
         feed: ReleaseFeed,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.installedVersion = installedVersion
        self.feed = feed
        self.defaults = defaults
        self.now = now
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        // Remembered so the update stays offered after a relaunch, until the
        // next daily check or until the newer copy is the one running.
        if let installedVersion,
           let known = defaults.string(forKey: Self.latestKnownKey).flatMap(AppVersion.init),
           known > installedVersion {
            availableVersion = known
        }
    }

    convenience init(defaults: UserDefaults = .standard) {
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        self.init(installedVersion: AppVersion(installed),
                  feed: GitHubReleaseFeed(userAgent: "Switchboard/\(installed)"),
                  defaults: defaults)
    }

    /// Starts the automatic schedule. Calling it again does nothing.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(fire: Date().addingTimeInterval(Self.launchDelaySeconds),
                          interval: Self.tickIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.checkIfDue() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The scheduled path: only when switched on and a day has passed since
    /// the last check that reached GitHub.
    @discardableResult
    func checkIfDue() -> Task<Void, Never>? {
        guard checksAutomatically,
              Self.isDue(lastSuccess: defaults.object(forKey: Self.lastSuccessKey) as? Date, now: now()) else { return nil }
        return check(userInitiated: false)
    }

    /// Joins a check already under way instead of sending a second request.
    /// A person who asked always hears the outcome; the schedule only speaks
    /// up about a version it has not announced before.
    @discardableResult
    func check(userInitiated: Bool) -> Task<Void, Never> {
        if userInitiated { someoneIsWaiting = true }
        if let inFlight { return inFlight }
        let task = Task { await self.runCheck() }
        inFlight = task
        return task
    }

    static func isDue(lastSuccess: Date?, now: Date) -> Bool {
        guard let lastSuccess else { return true }
        let elapsed = now.timeIntervalSince(lastSuccess)
        // A negative gap means the clock moved back; waiting for it to catch up could take days.
        return elapsed >= checkIntervalSeconds || elapsed < 0
    }

    private func runCheck() async {
        isChecking = true
        defer {
            isChecking = false
            someoneIsWaiting = false
            inFlight = nil
        }
        let latest: AppVersion
        let installed: AppVersion
        do {
            guard let installedVersion else { throw UpdateCheckError.unreadableInstalledVersion }
            installed = installedVersion
            latest = try await feed.latestVersion()
        } catch {
            logger.error("Update check failed: \(String(describing: error), privacy: .public)")
            if someoneIsWaiting { onReport?(.failed) }
            return
        }
        defaults.set(now(), forKey: Self.lastSuccessKey)
        logger.info("Latest release \(latest.description, privacy: .public), installed \(installed.description, privacy: .public)")

        guard latest > installed else {
            availableVersion = nil
            defaults.removeObject(forKey: Self.latestKnownKey)
            if someoneIsWaiting { onReport?(.upToDate(installed: installed)) }
            return
        }
        let alreadyAnnounced = availableVersion == latest
        availableVersion = latest
        defaults.set(latest.description, forKey: Self.latestKnownKey)
        if someoneIsWaiting || !alreadyAnnounced {
            onReport?(.available(latest: latest, installed: installed))
        }
    }
}
