import Foundation

// Dock, Finder and SystemUIServer only reread these domains on launch, so a
// preference write is only half the job.
enum SystemRestart {
    static func killall(_ target: RestartTarget) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [target.rawValue]
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func summary(for targets: Set<RestartTarget>) -> String {
        let names = RestartTarget.allCases.filter(targets.contains).map(\.label)
        switch names.count {
        case 0: return ""
        case 1: return "Restart \(names[0])"
        case 2: return "Restart \(names[0]) and \(names[1])"
        default: return "Restart \(names.dropLast().joined(separator: ", ")) and \(names.last!)"
        }
    }

    static func requirement(for targets: Set<RestartTarget>) -> String {
        let names = RestartTarget.allCases.filter(targets.contains).map(\.label)
        if names.count == 1 { return "\(names[0]) needs to restart" }
        return "System services need to restart"
    }
}
