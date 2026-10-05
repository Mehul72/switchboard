import XCTest

final class AppVersionTests: XCTestCase {
    func testReadsBundleVersionsAndReleaseTags() {
        XCTAssertEqual(AppVersion("1.1.4")?.parts, [1, 1, 4])
        XCTAssertEqual(AppVersion("v1.1.4")?.parts, [1, 1, 4])
        XCTAssertEqual(AppVersion("2")?.parts, [2])
        XCTAssertEqual(AppVersion("v1.10")?.description, "1.10")
    }

    func testRefusesAnythingThatIsNotAPlainVersion() {
        for text in ["", "v", "V1.2", "1..2", "1.2.", ".1", "1.2.x", "1.2.0-beta", "nightly",
                     " 1.2", "1.2.3.4.5", "١.٢", "+1.2", "-1.2", "99999999999999999999.0"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testComparesNumericallyNotAlphabetically() throws {
        XCTAssertLessThan(try version("1.9.9"), try version("1.10.0"))
        XCTAssertLessThan(try version("1.99.99"), try version("2.0"))
        XCTAssertLessThan(try version("1.1.4"), try version("v1.1.5"))
        XCTAssertGreaterThan(try version("1.1.4.1"), try version("1.1.4"))
    }

    func testMissingPartsCountAsZero() throws {
        XCTAssertEqual(try version("1.2"), try version("1.2.0"))
        XCTAssertEqual(try version("v1.2.0.0"), try version("1.2"))
        XCTAssertFalse(try version("1.2") < version("1.2.0"))
    }

    private func version(_ text: String) throws -> AppVersion {
        try XCTUnwrap(AppVersion(text))
    }
}

final class GitHubReleaseFeedTests: XCTestCase {
    override func tearDown() {
        StubResponses.respond = nil
        super.tearDown()
    }

    func testReadsTheTagOfTheLatestRelease() async throws {
        var sent: URLRequest?
        StubResponses.respond = { request in
            sent = request
            return (200, Data(#"{"tag_name":"v1.1.5","name":"Switchboard 1.1.5","draft":false,"prerelease":false}"#.utf8))
        }
        let latest = try await stubbedFeed().latestVersion()

        XCTAssertEqual(latest.parts, [1, 1, 5])
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.url, GitHubReleaseFeed.latestReleaseEndpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Switchboard/1.1.4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    func testRateLimitAndMissingReleaseAreFailures() async {
        for status in [403, 404, 429, 500] {
            StubResponses.respond = { _ in (status, Data(#"{"message":"API rate limit exceeded"}"#.utf8)) }
            do {
                _ = try await stubbedFeed().latestVersion()
                XCTFail("status \(status) should fail")
            } catch UpdateCheckError.status(let code) {
                XCTAssertEqual(code, status)
            } catch {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testATagThatIsNotAVersionIsAFailure() async {
        StubResponses.respond = { _ in (200, Data(#"{"tag_name":"nightly-2026-09-27"}"#.utf8)) }
        do {
            _ = try await stubbedFeed().latestVersion()
            XCTFail("an unreadable tag should fail")
        } catch UpdateCheckError.unreadableTag(let tag) {
            XCTAssertEqual(tag, "nightly-2026-09-27")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAMalformedBodyIsAFailure() async {
        for body in ["", "<html>", #"{"name":"no tag"}"#, #"{"tag_name":5}"#] {
            StubResponses.respond = { _ in (200, Data(body.utf8)) }
            do {
                _ = try await stubbedFeed().latestVersion()
                XCTFail("\(body) should fail")
            } catch {
                XCTAssertTrue(error is DecodingError, "\(body): \(error)")
            }
        }
    }

    /// A server that accepts the connection and never answers must not hold the check open.
    func testASilentServerTimesOut() async throws {
        let sinkhole = try Sinkhole()
        defer { sinkhole.close() }
        let feed = GitHubReleaseFeed(
            userAgent: "Switchboard/test",
            session: GitHubReleaseFeed.makeSession(requestTimeoutSeconds: 0.5, totalTimeoutSeconds: 1),
            endpoint: URL(string: "http://127.0.0.1:\(sinkhole.port)/releases/latest")!
        )
        let started = Date()
        do {
            _ = try await feed.latestVersion()
            XCTFail("a silent server should time out")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    private func stubbedFeed() -> GitHubReleaseFeed {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubResponses.self]
        return GitHubReleaseFeed(userAgent: "Switchboard/1.1.4", session: URLSession(configuration: configuration))
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var feed: FakeFeed!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var reports: [UpdateChecker.Report] = []

    override func setUp() async throws {
        try await super.setUp()
        defaults = InMemoryDefaults()
        feed = FakeFeed()
        reports = []
    }

    override func tearDown() async throws {
        defaults = nil
        try await super.tearDown()
    }

    func testAskingReportsANewerRelease() async {
        feed.next = .success(AppVersion("1.1.5")!)
        let checker = makeChecker(installed: "1.1.4")
        await checker.check(userInitiated: true).value

        XCTAssertEqual(reports, [.available(latest: AppVersion("1.1.5")!, installed: AppVersion("1.1.4")!)])
        XCTAssertEqual(checker.availableVersion?.description, "1.1.5")
        XCTAssertFalse(checker.isChecking)
    }

    func testAskingReportsUpToDateForTheSameOrAnOlderRelease() async {
        for (installed, latest) in [("1.1.4", "1.1.4"), ("1.2", "1.2.0"), ("1.2.0", "1.1.9")] {
            reports = []
            feed.next = .success(AppVersion(latest)!)
            let checker = makeChecker(installed: installed)
            await checker.check(userInitiated: true).value

            XCTAssertEqual(reports, [.upToDate(installed: AppVersion(installed)!)], "\(installed) vs \(latest)")
            XCTAssertNil(checker.availableVersion)
        }
    }

    func testAskingReportsAFailureAndDoesNotCountItAsACheck() async {
        feed.next = .failure(URLError(.notConnectedToInternet))
        let checker = makeChecker(installed: "1.1.4")
        await checker.check(userInitiated: true).value

        XCTAssertEqual(reports, [.failed])
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastSuccessKey))
        XCTAssertFalse(checker.isChecking)
    }

    func testAnUnreadableInstalledVersionFailsWithoutARequest() async {
        let checker = makeChecker(installed: "")
        await checker.check(userInitiated: true).value

        XCTAssertEqual(reports, [.failed])
        XCTAssertEqual(feed.calls, 0)
    }

    func testTheScheduleAnnouncesEachVersionOnce() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.5")!)
        await runScheduledCheck(checker)
        clock.addTimeInterval(UpdateChecker.checkIntervalSeconds)
        await runScheduledCheck(checker)

        XCTAssertEqual(feed.calls, 2)
        XCTAssertEqual(reports, [.available(latest: AppVersion("1.1.5")!, installed: AppVersion("1.1.4")!)])
        XCTAssertEqual(checker.availableVersion?.description, "1.1.5")

        feed.next = .success(AppVersion("1.1.6")!)
        clock.addTimeInterval(UpdateChecker.checkIntervalSeconds)
        await runScheduledCheck(checker)
        XCTAssertEqual(reports.last, .available(latest: AppVersion("1.1.6")!, installed: AppVersion("1.1.4")!))
        XCTAssertEqual(reports.count, 2)
    }

    func testTheScheduleStaysQuietWhenUpToDateOrFailing() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.4")!)
        await runScheduledCheck(checker)
        clock.addTimeInterval(UpdateChecker.checkIntervalSeconds)
        feed.next = .failure(URLError(.timedOut))
        await runScheduledCheck(checker)

        XCTAssertEqual(feed.calls, 2)
        XCTAssertEqual(reports, [])
    }

    func testAskingAgainRepeatsAnAlreadyAnnouncedVersion() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.5")!)
        await runScheduledCheck(checker)
        await checker.check(userInitiated: true).value

        XCTAssertEqual(reports.count, 2)
    }

    func testTheScheduleWaitsADayAfterASuccessfulCheck() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.4")!)
        await runScheduledCheck(checker)
        clock.addTimeInterval(UpdateChecker.checkIntervalSeconds - 1)
        await runScheduledCheck(checker)
        XCTAssertEqual(feed.calls, 1)

        clock.addTimeInterval(1)
        await runScheduledCheck(checker)
        XCTAssertEqual(feed.calls, 2)
    }

    func testTheScheduleRetriesAFailureAtTheNextTick() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .failure(URLError(.notConnectedToInternet))
        await runScheduledCheck(checker)
        clock.addTimeInterval(UpdateChecker.tickIntervalSeconds)
        await runScheduledCheck(checker)

        XCTAssertEqual(feed.calls, 2)
    }

    func testAClockMovedBackwardsDoesNotPostponeChecks() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.4")!)
        await runScheduledCheck(checker)
        clock.addTimeInterval(-3600)
        await runScheduledCheck(checker)

        XCTAssertEqual(feed.calls, 2)
    }

    func testTurningAutomaticChecksOffStopsTheScheduleButNotAsking() async {
        let checker = makeChecker(installed: "1.1.4")
        checker.checksAutomatically = false
        feed.next = .success(AppVersion("1.1.5")!)
        await runScheduledCheck(checker)
        XCTAssertEqual(feed.calls, 0)

        await checker.check(userInitiated: true).value
        XCTAssertEqual(feed.calls, 1)
        XCTAssertEqual(defaults.object(forKey: UpdateChecker.automaticKey) as? Bool, false)
        XCTAssertFalse(makeChecker(installed: "1.1.4").checksAutomatically)
    }

    func testAutomaticChecksStartOn() {
        XCTAssertTrue(makeChecker(installed: "1.1.4").checksAutomatically)
    }

    func testAKnownUpdateIsStillOfferedAfterRelaunchUntilInstalled() async {
        feed.next = .success(AppVersion("1.1.5")!)
        await runScheduledCheck(makeChecker(installed: "1.1.4"))

        let relaunched = makeChecker(installed: "1.1.4")
        XCTAssertEqual(relaunched.availableVersion?.description, "1.1.5")
        // The day has not passed, so a relaunch does not announce it again.
        await runScheduledCheck(relaunched)
        XCTAssertEqual(reports.count, 1)

        XCTAssertNil(makeChecker(installed: "1.1.5").availableVersion)
    }

    func testAReleaseThatIsWithdrawnStopsBeingOffered() async {
        let checker = makeChecker(installed: "1.1.4")
        feed.next = .success(AppVersion("1.1.5")!)
        await runScheduledCheck(checker)
        feed.next = .success(AppVersion("1.1.4")!)
        clock.addTimeInterval(UpdateChecker.checkIntervalSeconds)
        await runScheduledCheck(checker)

        XCTAssertNil(checker.availableVersion)
        XCTAssertNil(makeChecker(installed: "1.1.4").availableVersion)
    }

    func testAskingDuringAScheduledCheckJoinsItAndHearsTheOutcome() async {
        feed.next = .success(AppVersion("1.1.4")!)
        let checker = makeChecker(installed: "1.1.4")
        let scheduled = checker.checkIfDue()
        let joined = checker.check(userInitiated: true)
        XCTAssertEqual(scheduled, joined)
        await joined.value

        XCTAssertEqual(feed.calls, 1)
        XCTAssertEqual(reports, [.upToDate(installed: AppVersion("1.1.4")!)])
    }

    func testAskingTwiceSendsOneRequest() async {
        feed.next = .success(AppVersion("1.1.5")!)
        let checker = makeChecker(installed: "1.1.4")
        let first = checker.check(userInitiated: true)
        let second = checker.check(userInitiated: true)
        await first.value
        await second.value

        XCTAssertEqual(feed.calls, 1)
        XCTAssertEqual(reports.count, 1)
    }

    private func makeChecker(installed: String) -> UpdateChecker {
        let checker = UpdateChecker(installedVersion: AppVersion(installed), feed: feed,
                                    defaults: defaults, now: { [unowned self] in self.clock })
        checker.onReport = { [unowned self] report in self.reports.append(report) }
        return checker
    }

    /// Runs the scheduled path and waits for any request it started.
    private func runScheduledCheck(_ checker: UpdateChecker) async {
        await checker.checkIfDue()?.value
    }
}

private final class FakeFeed: ReleaseFeed, @unchecked Sendable {
    var next: Result<AppVersion, Error> = .failure(URLError(.unknown))
    private(set) var calls = 0

    func latestVersion() async throws -> AppVersion {
        calls += 1
        return try next.get()
    }
}

private final class StubResponses: URLProtocol {
    static var respond: ((URLRequest) -> (status: Int, body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let respond = Self.respond, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = respond(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A local port that completes TCP connections in the kernel backlog but
/// never reads or answers, the way a stalled server or captive portal does.
private final class Sinkhole {
    let port: UInt16
    private let descriptor: Int32

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
        }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard bound == 0, listen(descriptor, 4) == 0, named == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(descriptor)
            throw POSIXError(code)
        }
        self.descriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    func close() {
        Darwin.close(descriptor)
    }
}
