import Foundation

// Dock, Finder and SystemUIServer only reread these domains on launch, so a
// preference write is only half the job.
enum SystemRestart {
    static func killall(_ target: RestartTarget) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [target.rawValue]
        task.standardError = FileHandle.nullDevice
        try? task.run()
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
}
