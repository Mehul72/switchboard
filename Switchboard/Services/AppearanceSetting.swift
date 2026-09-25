import AppKit
import Combine

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// Nil hands the choice back to macOS. The high-contrast names cannot be
    /// created directly; AppKit layers Increase Contrast onto these itself.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Switchboard's own light or dark mode. Every window and panel inherits the
/// application appearance, so setting it once covers the whole app without
/// touching the system-wide setting.
@MainActor
final class AppearanceSetting: ObservableObject {
    static let defaultsKey = "AppearanceChoice"

    @Published var choice: AppearanceChoice {
        didSet {
            defaults.set(choice.rawValue, forKey: Self.defaultsKey)
            apply()
        }
    }

    private let defaults: UserDefaults
    private let applyAppearance: @MainActor (NSAppearance?) -> Void

    init(defaults: UserDefaults = .standard,
         applyAppearance: @escaping @MainActor (NSAppearance?) -> Void = { NSApp.appearance = $0 }) {
        self.defaults = defaults
        self.applyAppearance = applyAppearance
        // An unknown stored value, from a newer or damaged preference, falls back to the system.
        choice = defaults.string(forKey: Self.defaultsKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
        apply()
    }

    private func apply() {
        applyAppearance(choice.appearance)
    }
}
