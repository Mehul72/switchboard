import Foundation

struct ScalingDisplay: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let nativeWidth: Int
    let nativeHeight: Int
    let isBuiltIn: Bool
    let unavailableReason: String?

    var resolutionLabel: String { "\(nativeWidth) × \(nativeHeight)" }
}

struct DisplayScalePreset: Identifiable, Equatable {
    let id: String
    let width: Int
    let height: Int
    let percent: Int

    var resolutionLabel: String { "\(width) × \(height)" }
    var title: String { "\(percent)% · \(resolutionLabel)" }

    static let maximumRenderDimension = 8192
    static let maximumRenderPixels = 33_554_432

    var isValid: Bool {
        guard width >= 800, height >= 600,
              width <= Self.maximumRenderDimension / 2,
              height <= Self.maximumRenderDimension / 2,
              (100...200).contains(percent) else { return false }
        return width * height * 4 <= Self.maximumRenderPixels
    }

    static func choices(width: Int, height: Int) -> [DisplayScalePreset] {
        guard (800...16384).contains(width), (600...16384).contains(height) else { return [] }
        var seen = Set<String>()
        return [100, 110, 125, 150, 175, 200].compactMap { percent in
            let factor = Double(percent) / 100
            let scaledWidth = Int((Double(width) / factor / 2).rounded()) * 2
            let scaledHeight = Int((Double(height) / factor / 2).rounded()) * 2
            let preset = DisplayScalePreset(id: "\(scaledWidth)x\(scaledHeight)",
                                            width: scaledWidth, height: scaledHeight, percent: percent)
            guard preset.isValid, seen.insert(preset.id).inserted else { return nil }
            return preset
        }
    }
}

@MainActor
protocol DisplayScalingBackendProtocol: AnyObject {
    func displays() throws -> [ScalingDisplay]
    func start(displayID: UInt32, preset: DisplayScalePreset) async throws
    func stop() throws
    func isSessionValid() -> Bool
}

enum DisplayScalingError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}
