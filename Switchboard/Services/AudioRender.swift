import Accelerate
import CoreAudio

/// Lays a tapped app's samples onto whatever channel layout the chosen output
/// device actually has.
///
/// A device-independent tap always hands over two interleaved channels, but the
/// destination is now whatever the user picked and need not match: a call
/// headset carries one channel, an interface can carry eight, and a device that
/// also records puts its own input in front of the tap in the same buffer list.
/// Copying samples straight across ignores all three shapes. Stereo poured into
/// a mono buffer plays an octave low and half as long, and reading buffer zero
/// on a device with a microphone plays the microphone instead of the app.
///
/// Everything here runs on the realtime audio thread, so it allocates nothing,
/// takes no locks, and makes one pass over the samples.
enum AudioRender {
    /// How many interleaved frames fit in a buffer of `bytes`.
    static func frameCount(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// Which input buffer carries the tap.
    ///
    /// An aggregate presents its sub-device's own input first and the tap after
    /// it, so on an output device that also records, the tap is not buffer
    /// zero. It is the last buffer whose channel count matches what the tap
    /// announced. When nothing matches and the device brought no input of its
    /// own, a lone buffer has nowhere else to have come from and is the tap.
    /// Guessing between several would play the device's own microphone out of
    /// its speakers, so the app stays silent instead.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var loneBuffer: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mData != nil && buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { loneBuffer = index }
        }
        return loneBuffer
    }

    /// Which source channel feeds one output channel, or nil when the device
    /// has more channels than the source can fill and the rest must stay quiet.
    static func sourceChannel(forOutputChannel outputChannel: Int,
                              sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        // A mono source belongs in both front channels, not only the left one.
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    /// Clears every output frame from `frame` onward.
    ///
    /// Core Audio hands the output buffer over dirty, holding whatever it last
    /// put in that memory. Frames with no samples behind them, the tail of a
    /// buffer longer than the source or a whole cycle with no tap to read, play
    /// back as a fragment of older audio if they are left alone.
    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frameCount(bytes: buffer.mDataByteSize,
                                       channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    /// Scales one interleaved source buffer by `gain` onto the output and
    /// answers how many frames it wrote. Whatever it does not write it
    /// silences, so callers never have to think about the tail.
    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        var written = 0
        defer { silence(output, from: written) }

        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        // Short buffers decide the length: writing past the shorter of source
        // and destination walks off the end of somebody's allocation.
        var frames = frameCount(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        var hasWritableOutput = false
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            hasWritableOutput = true
            frames = min(frames, frameCount(bytes: buffer.mDataByteSize,
                                            channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0, hasWritableOutput else { return 0 }
        var scale = gain

        // The common case: one buffer wanting exactly the shape the tap
        // produced, so there is nothing to map and one pass does it.
        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &scale, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return written
        }

        // One channel to play into: sum the source channels rather than handing
        // over every other sample, which would halve the pitch and the length.
        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var foldScale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &foldScale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &foldScale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var didWriteAnySource = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                guard let sourceChannel = sourceChannel(forOutputChannel: firstOutputChannel + channel,
                                                        sourceChannels: sourceChannels) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                didWriteAnySource = true
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &scale,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = didWriteAnySource ? frames : 0
        return written
    }
}
