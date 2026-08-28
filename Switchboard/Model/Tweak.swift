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

    // Values come back from CFPreferences however they were written -- a float
    // 0 read back as an integer 0 still means the tweak is on.
    func matches(_ stored: Any?) -> Bool {
        guard let stored else { return false }
        switch self {
        case .bool(let value):
            guard let number = stored as? NSNumber else { return false }
            return number.boolValue == value
        case .int(let value):
            guard let number = stored as? NSNumber else { return false }
            return number.intValue == value
        case .float(let value):
            guard let number = stored as? NSNumber else { return false }
            return abs(number.doubleValue - value) < 0.0001
        case .string(let value):
            return (stored as? String) == value
        }
    }
}

enum Category: String, CaseIterable {
    case dock, finder, screenshots, speed, typing

    var label: String { rawValue.capitalized }
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

struct Choice: Equatable {
    let label: String
    let value: PrefValue
}

enum Control {
    case toggle
    case choice([Choice])
    case folder
}

struct Tweak: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let category: Category
    let domain: String
    let key: String
    let onValue: PrefValue
    let offValue: PrefValue?
    let restart: RestartTarget?
    let control: Control

    init(id: String,
         title: String,
         subtitle: String? = nil,
         category: Category,
         domain: String,
         key: String,
         onValue: PrefValue,
         offValue: PrefValue? = nil,
         restart: RestartTarget? = nil,
         control: Control = .toggle) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.domain = domain
        self.key = key
        self.onValue = onValue
        self.offValue = offValue
        self.restart = restart
        self.control = control
    }

    func matches(search: String) -> Bool {
        guard !search.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(search) { return true }
        return subtitle?.localizedCaseInsensitiveContains(search) ?? false
    }
}
