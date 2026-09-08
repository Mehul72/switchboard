import XCTest

private let speakers = "BuiltInSpeakerDevice"
private let airpods = "AirPods-Pro"
private let unplugged = "SomeInterfaceThatLeft"

final class AudioRoutingDeviceFilterTests: XCTestCase {
    func testSwitchboardsOwnAggregatesAreRecognised() {
        XCTAssertTrue(AudioRouting.isOwnDevice(uid: "com.Mehul72.switchboard.\(UUID().uuidString)"))
    }

    func testRealDevicesAreNotMistakenForOurs() {
        XCTAssertFalse(AudioRouting.isOwnDevice(uid: speakers))
        XCTAssertFalse(AudioRouting.isOwnDevice(uid: "com.Mehul72.switchboardish"))
        XCTAssertFalse(AudioRouting.isOwnDevice(uid: ""))
    }

    func testAPlayableDeviceIsOffered() {
        XCTAssertTrue(AudioRouting.isSelectableOutput(uid: speakers, isAlive: true,
                                                      hasOutputStreams: true))
    }

    func testAMicrophoneIsNotAnOutput() {
        XCTAssertFalse(AudioRouting.isSelectableOutput(uid: "BuiltInMicrophoneDevice",
                                                       isAlive: true, hasOutputStreams: false))
    }

    func testAnUnpluggedDeviceIsNotOffered() {
        XCTAssertFalse(AudioRouting.isSelectableOutput(uid: speakers, isAlive: false,
                                                       hasOutputStreams: true))
    }

    /// Routing an app into the aggregate that is already moving it would feed
    /// the renderer its own output.
    func testOurOwnRenderAggregateIsNeverOffered() {
        XCTAssertFalse(AudioRouting.isSelectableOutput(uid: "com.Mehul72.switchboard.abc",
                                                       isAlive: true, hasOutputStreams: true))
    }
}

/// The slider is continuous and the row rounds to whole percent, so a value
/// that reads 100% has to be treated as 100%. Otherwise a tap, and the audio
/// privacy indicator with it, outlives the reason for it.
final class AudioRoutingFullVolumeTests: XCTestCase {
    func testExactlyFullIsFullVolume() {
        XCTAssertTrue(AudioRouting.isFullVolume(1))
    }

    func testAValueThatStillDisplaysAsFullCountsAsFull() {
        XCTAssertTrue(AudioRouting.isFullVolume(0.9998))
        XCTAssertTrue(AudioRouting.isFullVolume(0.996))
    }

    func testAValueThatDisplaysAsNinetyNineDoesNot() {
        XCTAssertFalse(AudioRouting.isFullVolume(0.99))
        XCTAssertFalse(AudioRouting.isFullVolume(0.5))
        XCTAssertFalse(AudioRouting.isFullVolume(0))
    }
}

final class AudioRoutingEffectiveDeviceTests: XCTestCase {
    private let available: Set<String> = [speakers, airpods]

    func testNoChoiceMeansTheSystemDefault() {
        XCTAssertEqual(AudioRouting.effectiveDeviceUID(selected: nil,
                                                       available: available,
                                                       systemDefault: airpods), airpods)
    }

    func testAChosenDeviceThatIsPresentIsUsed() {
        XCTAssertEqual(AudioRouting.effectiveDeviceUID(selected: speakers,
                                                       available: available,
                                                       systemDefault: airpods), speakers)
    }

    /// Unplugging an interface should hand the app back to the default, not
    /// mute it until someone reopens Switchboard.
    func testAChosenDeviceThatLeftFallsBackToTheDefault() {
        XCTAssertEqual(AudioRouting.effectiveDeviceUID(selected: unplugged,
                                                       available: available,
                                                       systemDefault: airpods), airpods)
    }

    func testNoDevicesAtAllResolvesToNothing() {
        XCTAssertNil(AudioRouting.effectiveDeviceUID(selected: speakers,
                                                     available: [],
                                                     systemDefault: nil))
    }

    func testMissingDeviceIsReportedOnlyWhenOneWasChosen() {
        XCTAssertTrue(AudioRouting.selectedDeviceIsMissing(selected: unplugged, available: available))
        XCTAssertFalse(AudioRouting.selectedDeviceIsMissing(selected: speakers, available: available))
        XCTAssertFalse(AudioRouting.selectedDeviceIsMissing(selected: nil, available: available))
    }
}

/// Every branch that decides whether a person's audio gets intercepted. A wrong
/// `true` here taps an app nobody asked to touch; a wrong `false` leaves a
/// chosen volume or device silently unapplied.
final class AudioRoutingNeedsTapTests: XCTestCase {
    private let available: Set<String> = [speakers, airpods]

    func testUntouchedAppOnTheDefaultIsLeftAlone() {
        XCTAssertFalse(AudioRouting.needsTap(gain: 1, selected: nil,
                                             effective: airpods, systemDefault: airpods))
    }

    func testReducedVolumeNeedsATap() {
        XCTAssertTrue(AudioRouting.needsTap(gain: 0.4, selected: nil,
                                            effective: airpods, systemDefault: airpods))
    }

    func testFullVolumeOnAnotherDeviceStillNeedsATap() {
        XCTAssertTrue(AudioRouting.needsTap(gain: 1, selected: speakers,
                                            effective: speakers, systemDefault: airpods))
    }

    /// Choosing the device that is already the default is not a reason to
    /// intercept anything.
    func testChoosingTheDefaultDeviceNeedsNoTap() {
        XCTAssertFalse(AudioRouting.needsTap(gain: 1, selected: airpods,
                                             effective: airpods, systemDefault: airpods))
    }

    /// The chosen device is gone, so the app is already back on the default by
    /// itself and needs nothing.
    func testAChosenDeviceThatLeftNeedsNoTapAtFullVolume() {
        XCTAssertFalse(AudioRouting.needsTap(gain: 1, selected: unplugged,
                                             effective: airpods, systemDefault: airpods))
    }

    func testAChosenDeviceThatLeftStillNeedsATapForVolume() {
        XCTAssertTrue(AudioRouting.needsTap(gain: 0.3, selected: unplugged,
                                            effective: airpods, systemDefault: airpods))
    }

    func testNowhereToRenderMeansNoTap() {
        XCTAssertFalse(AudioRouting.needsTap(gain: 0.2, selected: speakers,
                                             effective: nil, systemDefault: nil))
    }

    func testAChosenDeviceIsHonouredWhenNoDefaultIsKnown() {
        XCTAssertTrue(AudioRouting.needsTap(gain: 1, selected: speakers,
                                            effective: speakers, systemDefault: nil))
    }

    /// The slider tolerance has to reach this decision too, or a drag back to
    /// the top leaves the tap running.
    func testAValueDisplayingAsFullReleasesTheTap() {
        XCTAssertFalse(AudioRouting.needsTap(gain: 0.9998, selected: nil,
                                             effective: airpods, systemDefault: airpods))
    }

    func testResolutionAndTapDecisionAgreeOnAMissingDevice() {
        let effective = AudioRouting.effectiveDeviceUID(selected: unplugged,
                                                        available: available,
                                                        systemDefault: airpods)
        XCTAssertEqual(effective, airpods)
        XCTAssertFalse(AudioRouting.needsTap(gain: 1, selected: unplugged,
                                             effective: effective, systemDefault: airpods))
    }
}

/// The enumeration against whatever this Mac actually has plugged in. Weaker
/// than the pure tests above by necessity, but it is the only thing that
/// catches a filter that quietly rejects every real device.
final class AudioOutputDeviceEnumerationTests: XCTestCase {
    func testEveryOfferedDeviceIsNamedAndNotOneOfOurs() {
        let devices = AppAudioEngine.outputDevices()

        XCTAssertFalse(devices.isEmpty, "this Mac reports no output device at all")
        for device in devices {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty, "an unnamed device cannot be picked from a menu")
            XCTAssertFalse(AudioRouting.isOwnDevice(uid: device.uid))
        }
    }

    /// A saved route remembers a UID, so two devices sharing one would send an
    /// app somewhere the person did not choose.
    func testOfferedDevicesHaveDistinctIdentifiers() {
        let devices = AppAudioEngine.outputDevices()
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
    }

    func testTheSystemDefaultIsAmongTheOfferedDevices() {
        guard let defaultUID = AppAudioEngine.systemDefaultOutputUID() else {
            return XCTFail("this Mac reports no default output device")
        }
        XCTAssertTrue(AppAudioEngine.outputDevices().contains { $0.uid == defaultUID })
    }
}

/// Routes outlive a launch, so what goes into defaults has to come back out
/// intact, and anything unexpected in there must not take the app down.
final class AudioRoutePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "switchboard.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRoutesSurviveARoundTrip() {
        let routes = ["com.apple.Music": speakers, "com.apple.Safari": airpods]

        AppAudioEngine.persistRoutes(routes, in: defaults)

        XCTAssertEqual(AppAudioEngine.savedRoutes(in: defaults), routes)
    }

    func testNoRoutesReadsBackEmpty() {
        XCTAssertEqual(AppAudioEngine.savedRoutes(in: defaults), [:])
    }

    /// Reset writes an empty set, which has to clear the key rather than leave
    /// the previous routes sitting there.
    func testPersistingNothingClearsWhatWasThere() {
        AppAudioEngine.persistRoutes(["com.apple.Music": speakers], in: defaults)

        AppAudioEngine.persistRoutes([:], in: defaults)

        XCTAssertEqual(AppAudioEngine.savedRoutes(in: defaults), [:])
        XCTAssertNil(defaults.object(forKey: AppAudioEngine.routesDefaultsKey))
    }

    func testNonStringValuesAreDroppedRatherThanCrashing() {
        defaults.set(["com.apple.Music": speakers, "broken": 42],
                     forKey: AppAudioEngine.routesDefaultsKey)

        XCTAssertEqual(AppAudioEngine.savedRoutes(in: defaults), ["com.apple.Music": speakers])
    }
}
