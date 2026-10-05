import AppKit
import CoreGraphics
import ImageIO
import NaturalLanguage
import Vision

/// The parts of a screen text capture that leave the app: the system's
/// selection UI and Vision. A value, so tests can stand in for both. Every
/// completion runs on the main thread.
struct ScreenTextSource {
    var selectRegion: (@escaping (Result<Data, Error>) -> Void) -> Void
    var recognise: (Data, @escaping (Result<String, Error>) -> Void) -> Void
    /// Answers true once a sample has been read, which is when macOS has its
    /// recognition models compiled.
    var prepare: (@escaping (Bool) -> Void) -> Void
    /// How long after launch `prepare` runs, to stay clear of login.
    var prepareDelaySeconds: TimeInterval

    static let live = ScreenTextSource(selectRegion: TextCapture.selectRegion,
                                       recognise: TextCapture.recogniseInBackground,
                                       prepare: TextCapture.prepareRecognition,
                                       prepareDelaySeconds: 20)
}

/// Drag a region, get its text on the clipboard. macOS can recognise text in an
/// image you already have, but offers no way to grab text off the screen
/// itself, which is the part people actually want.
enum TextCapture {
    enum CaptureError: LocalizedError, Equatable {
        case cancelled
        case permissionDenied
        case captureFailed
        case unreadableImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Selection cancelled."
            case .permissionDenied:
                return "Allow Switchboard to record the screen in Privacy & Security, then try again."
            case .captureFailed: return "macOS could not capture that region."
            case .unreadableImage: return "The captured region could not be read."
            case .noTextFound: return "No text found in that selection."
            }
        }
    }

    private struct RecognisedLine {
        let text: String
        let box: CGRect
    }

    private static let recognitionQueue = DispatchQueue(
        label: "com.Mehul72.switchboard.text-recognition",
        qos: .userInitiated
    )

    /// Runs Apple's own selection UI, so the crosshair, escape-to-cancel and
    /// Screen Recording prompt all behave exactly as they do system-wide.
    ///
    /// Hands back the picture of the chosen region, on the main thread.
    /// Reading it is a separate step because it can take far longer than the
    /// selection, and the app has to stay usable while it runs.
    static func selectRegion(completion: @escaping (Result<Data, Error>) -> Void) {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            completion(.failure(CaptureError.permissionDenied))
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchboard-ocr-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -o no window shadow, -x no capture sound
        task.arguments = ["-i", "-o", "-x", url.path]
        task.terminationHandler = { process in
            let status = process.terminationStatus
            // Not the recognition queue: a read already under way there would
            // hold this up, and the selection would look as if it never ended.
            DispatchQueue.global(qos: .userInitiated).async {
                let picture = try? Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)

                let result: Result<Data, Error>
                if let picture, !picture.isEmpty {
                    result = .success(picture)
                } else if !CGPreflightScreenCaptureAccess() {
                    result = .failure(CaptureError.permissionDenied)
                } else if status == 0 {
                    result = .failure(CaptureError.cancelled)
                } else {
                    result = .failure(CaptureError.captureFailed)
                }

                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }

        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                completion(.failure(CaptureError.captureFailed))
            }
        }
    }

    /// Reads the text in a picture off the main thread and answers on it.
    static func recogniseInBackground(_ picture: Data, completion: @escaping (Result<String, Error>) -> Void) {
        recognitionQueue.async {
            let result = recognise(picture)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Reads a small drawn sample so macOS compiles its recognition models
    /// now. It does that the first time an app reads text on a system build,
    /// which was measured at 27 seconds, and otherwise it lands on someone's
    /// first capture. Answers true once the sample was read.
    static func prepareRecognition(completion: @escaping (Bool) -> Void) {
        // Same queue as real reads, so a capture started meanwhile waits for
        // this work instead of repeating it.
        recognitionQueue.async(qos: .utility) {
            var didRead = false
            if let sample = sampleTextImage(), case .success = recognise(sample) {
                didRead = true
            }
            DispatchQueue.main.async { completion(didRead) }
        }
    }

    private static func sampleTextImage() -> CGImage? {
        let width = 360
        let height = 90
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let sample = NSAttributedString(string: "Switchboard 2026", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 34, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 18, y: 30)
        CTLineDraw(CTLineCreateWithAttributedString(sample), context)
        return context.makeImage()
    }

    static func recognise(_ imageData: Data) -> Result<String, Error> {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failure(CaptureError.unreadableImage)
        }
        return recognise(cgImage)
    }

    private static func recognise(_ cgImage: CGImage) -> Result<String, Error> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return .failure(error)
        }

        let lines = (request.results ?? []).compactMap { observation -> RecognisedLine? in
            guard let text = observation.topCandidates(1).first?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return RecognisedLine(text: text, box: observation.boundingBox)
        }
        guard !lines.isEmpty else { return .failure(CaptureError.noTextFound) }
        return .success(readingOrder(lines))
    }

    /// Vision does not promise that observations arrive in reading order.
    /// Group nearby observations into visual rows, then read each row from
    /// left to right and the rows from top to bottom.
    private static func readingOrder(_ lines: [RecognisedLine]) -> String {
        var rows: [[RecognisedLine]] = []

        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                let tolerance = max(first.box.height, line.box.height) * 0.45
                return abs(first.box.midY - line.box.midY) <= tolerance
            }) {
                rows[rowIndex].append(line)
            } else {
                rows.append([line])
            }
        }

        rows.sort {
            ($0.map(\.box.midY).max() ?? 0) > ($1.map(\.box.midY).max() ?? 0)
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    @discardableResult
    static func copyToClipboard(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Best guess at what language the captured text is in, so text that is
    /// already English is never sent through translation.
    static func dominantLanguage(of text: String) -> Locale.Language? {
        let recogniser = NLLanguageRecognizer()
        recogniser.processString(text)
        guard let code = recogniser.dominantLanguage?.rawValue else { return nil }
        return Locale.Language(identifier: code)
    }

    static func isEnglish(_ language: Locale.Language?) -> Bool {
        language?.languageCode?.identifier == "en"
    }
}
