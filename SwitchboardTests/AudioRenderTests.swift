import CoreAudio
import XCTest

/// Owns one interleaved buffer list for the duration of a test.
///
/// Core Audio hands its buffers over dirty, so these are filled with a value
/// that is obviously not silence: a test that expects zeroes has to prove the
/// render wrote them.
private final class TestBuffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []
    private let frames: Int

    init(channelCounts: [Int], frames: Int, fill: Float = -99) {
        self.frames = frames
        list = AudioBufferList.allocate(maximumBuffers: channelCounts.count)
        for (index, channels) in channelCounts.enumerated() {
            let sampleCount = max(channels * frames, 1)
            let memory = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
            memory.initialize(repeating: fill, count: sampleCount)
            storage.append(memory)
            list[index] = AudioBuffer(mNumberChannels: UInt32(channels),
                                      mDataByteSize: UInt32(channels * frames * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(memory))
        }
    }

    deinit {
        for pointer in storage { pointer.deallocate() }
        free(list.unsafeMutablePointer)
    }

    /// Writes interleaved samples into one buffer, laid out channel by channel
    /// within each frame.
    func fill(buffer index: Int = 0, with samples: [Float]) {
        let destination = storage[index]
        for (offset, value) in samples.enumerated() { destination[offset] = value }
    }

    func samples(buffer index: Int = 0) -> [Float] {
        let channels = Int(list[index].mNumberChannels)
        return Array(UnsafeBufferPointer(start: storage[index], count: channels * frames))
    }

    /// A buffer the HAL declared but gave no memory for.
    func dropData(buffer index: Int) {
        list[index].mData = nil
    }
}

final class AudioRenderFrameCountTests: XCTestCase {
    func testFrameCountDividesByChannelsAndSampleSize() {
        XCTAssertEqual(AudioRender.frameCount(bytes: 64, channels: 2), 8)
        XCTAssertEqual(AudioRender.frameCount(bytes: 64, channels: 1), 16)
        XCTAssertEqual(AudioRender.frameCount(bytes: 64, channels: 8), 2)
    }

    func testZeroChannelsHasNoFrames() {
        XCTAssertEqual(AudioRender.frameCount(bytes: 64, channels: 0), 0)
    }

    func testPartialFrameIsNotCounted() {
        XCTAssertEqual(AudioRender.frameCount(bytes: 12, channels: 2), 1)
    }
}

final class AudioRenderChannelMapTests: XCTestCase {
    func testStereoMapsStraightAcross() {
        XCTAssertEqual(AudioRender.sourceChannel(forOutputChannel: 0, sourceChannels: 2), 0)
        XCTAssertEqual(AudioRender.sourceChannel(forOutputChannel: 1, sourceChannels: 2), 1)
    }

    func testMonoSourceFillsBothFrontChannels() {
        XCTAssertEqual(AudioRender.sourceChannel(forOutputChannel: 0, sourceChannels: 1), 0)
        XCTAssertEqual(AudioRender.sourceChannel(forOutputChannel: 1, sourceChannels: 1), 0)
    }

    func testChannelsBeyondTheSourceStaySilent() {
        XCTAssertNil(AudioRender.sourceChannel(forOutputChannel: 2, sourceChannels: 2))
        XCTAssertNil(AudioRender.sourceChannel(forOutputChannel: 7, sourceChannels: 2))
        XCTAssertNil(AudioRender.sourceChannel(forOutputChannel: 2, sourceChannels: 1))
    }
}

/// Picking the wrong input buffer plays the output device's own microphone out
/// of its speakers, so each shape the HAL can present is pinned here.
final class AudioRenderTapBufferTests: XCTestCase {
    func testLoneBufferIsTheTapEvenWhenItsShapeIsUnexpected() {
        let buffers = TestBuffers(channelCounts: [2], frames: 4)
        XCTAssertEqual(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 2), 0)
        XCTAssertEqual(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 6), 0)
    }

    func testTapIsFoundAfterTheDevicesOwnMicrophone() {
        let buffers = TestBuffers(channelCounts: [1, 2], frames: 4)
        XCTAssertEqual(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 2), 1)
    }

    func testLastMatchingBufferWins() {
        let buffers = TestBuffers(channelCounts: [2, 1, 2], frames: 4)
        XCTAssertEqual(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 2), 2)
    }

    func testSeveralBuffersWithNoMatchAreNotGuessedAt() {
        let buffers = TestBuffers(channelCounts: [1, 4], frames: 4)
        XCTAssertNil(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 2))
    }

    func testBufferWithoutMemoryIsSkipped() {
        let buffers = TestBuffers(channelCounts: [2, 2], frames: 4)
        buffers.dropData(buffer: 1)
        XCTAssertEqual(AudioRender.tapBufferIndex(in: buffers.list, tapChannels: 2), 0)
    }
}

final class AudioRenderOutputTests: XCTestCase {
    /// The shape almost every Mac presents: stereo tap, stereo speakers.
    func testStereoOntoStereoScalesEverySample() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 2, 3, 4])
        let output = TestBuffers(channelCounts: [2], frames: 2)

        let written = AudioRender.render(source: source.list[0], into: output.list, gain: 0.5)

        XCTAssertEqual(written, 2)
        XCTAssertEqual(output.samples(), [0.5, 1, 1.5, 2])
    }

    /// A call headset carries one channel. Handing it every other sample would
    /// play the app an octave low, so the channels are summed instead.
    func testStereoFoldsIntoOneChannel() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 3, 2, 6])
        let output = TestBuffers(channelCounts: [1], frames: 2)

        let written = AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(written, 2)
        XCTAssertEqual(output.samples(), [2, 4])
    }

    func testFoldAppliesGain() {
        let source = TestBuffers(channelCounts: [2], frames: 1)
        source.fill(with: [1, 3])
        let output = TestBuffers(channelCounts: [1], frames: 1)

        AudioRender.render(source: source.list[0], into: output.list, gain: 0.5)

        XCTAssertEqual(output.samples(), [1])
    }

    /// An interface with eight channels gets the stereo pair up front and
    /// silence behind it, never a repeat of the source.
    func testChannelsBeyondTheSourceAreCleared() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 2, 3, 4])
        let output = TestBuffers(channelCounts: [8], frames: 2)

        let written = AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(written, 2)
        XCTAssertEqual(output.samples(), [1, 2, 0, 0, 0, 0, 0, 0,
                                          3, 4, 0, 0, 0, 0, 0, 0])
    }

    func testMonoSourceReachesBothStereoChannels() {
        let source = TestBuffers(channelCounts: [1], frames: 2)
        source.fill(with: [1, 2])
        let output = TestBuffers(channelCounts: [2], frames: 2)

        AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(output.samples(), [1, 1, 2, 2])
    }

    func testSourceSpreadsAcrossSeveralOutputBuffers() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 2, 3, 4])
        let output = TestBuffers(channelCounts: [1, 1], frames: 2)

        AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(output.samples(buffer: 0), [1, 3])
        XCTAssertEqual(output.samples(buffer: 1), [2, 4])
    }

    /// Frames with no samples behind them play as a fragment of older audio if
    /// they are left as the HAL handed them over.
    func testTailBeyondTheSourceIsSilenced() {
        let source = TestBuffers(channelCounts: [2], frames: 1)
        source.fill(with: [1, 2])
        let output = TestBuffers(channelCounts: [2], frames: 3)

        let written = AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(written, 1)
        XCTAssertEqual(output.samples(), [1, 2, 0, 0, 0, 0])
    }

    func testShortOutputStopsAtItsOwnLength() {
        let source = TestBuffers(channelCounts: [2], frames: 4)
        source.fill(with: [1, 2, 3, 4, 5, 6, 7, 8])
        let output = TestBuffers(channelCounts: [2], frames: 2)

        let written = AudioRender.render(source: source.list[0], into: output.list, gain: 1)

        XCTAssertEqual(written, 2)
        XCTAssertEqual(output.samples(), [1, 2, 3, 4])
    }

    func testSourceWithoutMemoryLeavesSilenceNotStaleAudio() {
        let output = TestBuffers(channelCounts: [2], frames: 2)
        let empty = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: nil)

        let written = AudioRender.render(source: empty, into: output.list, gain: 1)

        XCTAssertEqual(written, 0)
        XCTAssertEqual(output.samples(), [0, 0, 0, 0])
    }

    func testOutputWithoutMemoryWritesNothing() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 2, 3, 4])
        let output = TestBuffers(channelCounts: [2], frames: 2)
        output.dropData(buffer: 0)

        XCTAssertEqual(AudioRender.render(source: source.list[0], into: output.list, gain: 1), 0)
    }

    func testZeroChannelSourceWritesNothing() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        let output = TestBuffers(channelCounts: [2], frames: 2)
        var silent = source.list[0]
        silent.mNumberChannels = 0

        XCTAssertEqual(AudioRender.render(source: silent, into: output.list, gain: 1), 0)
        XCTAssertEqual(output.samples(), [0, 0, 0, 0])
    }

    func testMutingWritesZeroesRatherThanLeavingTheBuffer() {
        let source = TestBuffers(channelCounts: [2], frames: 2)
        source.fill(with: [1, 2, 3, 4])
        let output = TestBuffers(channelCounts: [2], frames: 2)

        AudioRender.render(source: source.list[0], into: output.list, gain: 0)

        XCTAssertEqual(output.samples(), [0, 0, 0, 0])
    }
}

final class AudioRenderSilenceTests: XCTestCase {
    func testSilenceClearsEveryBuffer() {
        let buffers = TestBuffers(channelCounts: [2, 1], frames: 2)

        AudioRender.silence(buffers.list)

        XCTAssertEqual(buffers.samples(buffer: 0), [0, 0, 0, 0])
        XCTAssertEqual(buffers.samples(buffer: 1), [0, 0])
    }

    func testSilenceFromAFrameLeavesEarlierFramesAlone() {
        let buffers = TestBuffers(channelCounts: [2], frames: 3)
        buffers.fill(with: [1, 2, 3, 4, 5, 6])

        AudioRender.silence(buffers.list, from: 1)

        XCTAssertEqual(buffers.samples(), [1, 2, 0, 0, 0, 0])
    }

    func testSilenceBeyondTheBufferDoesNothing() {
        let buffers = TestBuffers(channelCounts: [2], frames: 2)
        buffers.fill(with: [1, 2, 3, 4])

        AudioRender.silence(buffers.list, from: 5)

        XCTAssertEqual(buffers.samples(), [1, 2, 3, 4])
    }
}
