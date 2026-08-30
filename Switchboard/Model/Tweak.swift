import Foundation

enum PrefValue: Equatable {
    case bool(Bool)
    case int(Int)
    case float(Double)
    case string(String)

    var propertyListValue: CFPropertyList {
        switch self {
        case .bool(let value): return value as CFBoolean
        case .int(let value): return value as CFNumber
        case .float(let value): return value as CFNumber
        case .string(let value): return value as CFString
        }
    }

    func matches(_ stored: Any?) -> Bool {
        guard let stored else { return false }
        switch self {
        case .bool(let value): return (stored as? NSNumber)?.boolValue == value
        case .int(let value): return (stored as? NSNumber)?.intValue == value
        case .float(let value):
            guard let number = stored as? NSNumber else { return false }
            return abs(number.doubleValue - value) < 0.0001
        case .string(let value): return (stored as? String) == value
        }
    }
}

enum Category: String, CaseIterable {
    case everyday, files, capture, dock, audio, clipboard

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .everyday: return "sparkles"
        case .files: return "folder"
        case .capture: return "camera.viewfinder"
        case .dock: return "dock.rectangle"
        case .audio: return "speaker.wave.2"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

enum RestartTarget: String, CaseIterable {
    case dock = "Dock"
    case finder = "Finder"
    case systemUIServer = "SystemUIServer"

    var label: String {
        switch self {
        case .dock: return "Dock"
        case .finder: return "Finder"
        case .systemUIServer: return "menu bar"
        }
    }
}

struct PendingTranslation: Equatable {
    let text: String
    let source: Locale.Language
}

struct Choice: Equatable, Identifiable {
    let label: String
    let value: PrefValue
    var id: String { label }
}

enum Control {
    case toggle
    case choice([Choice])
    case folder
    case button(String)
}

struct PreferenceSpec {
    let domain: String
    let key: String
    let onValue: PrefValue
    let offValue: PrefValue?
    let restart: RestartTarget?
}

enum TweakBehavior {
    case preference(PreferenceSpec)
    case keepAwake
    case plainTextClipboard
    case mouseScrollDirection
    case quitOnClose
    case regionOCR
    case translateCaptures
}

struct Tweak: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let category: Category
    let symbol: String
    let control: Control
    let behavior: TweakBehavior
    let successMessage: String?

    init(id: String,
         title: String,
         subtitle: String? = nil,
         category: Category,
         symbol: String,
         domain: String,
         key: String,
         onValue: PrefValue,
         offValue: PrefValue? = nil,
         restart: RestartTarget? = nil,
         control: Control = .toggle,
         successMessage: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.symbol = symbol
        self.control = control
        self.successMessage = successMessage
        self.behavior = .preference(PreferenceSpec(domain: domain,
                                                   key: key,
                                                   onValue: onValue,
                                                   offValue: offValue,
                                                   restart: restart))
    }

    init(id: String,
         title: String,
         subtitle: String? = nil,
         category: Category,
         symbol: String,
         control: Control,
         behavior: TweakBehavior,
         successMessage: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.symbol = symbol
        self.control = control
        self.behavior = behavior
        self.successMessage = successMessage
    }

    var preference: PreferenceSpec? {
        guard case .preference(let preference) = behavior else { return nil }
        return preference
    }

    func matches(search: String) -> Bool {
        guard !search.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(search)
            || (subtitle?.localizedCaseInsensitiveContains(search) ?? false)
            || category.label.localizedCaseInsensitiveContains(search)
    }
}
