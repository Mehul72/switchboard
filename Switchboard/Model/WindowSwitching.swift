import Foundation

/// One card in the switcher: a window, or a running app with no windows.
struct SwitcherWindow: Identifiable, Equatable {
    let id: UInt32
    let pid: Int32
    let appName: String
    let title: String
    var isMinimized = false
    var isHidden = false
    var isWindowlessApp = false

    /// WindowServer numbers windows upward from 1, far below 2^31, so the top
    /// bit gives app entries IDs that cannot collide with a window's.
    static func windowlessApp(pid: Int32, appName: String, isHidden: Bool = false) -> Self {
        SwitcherWindow(id: 0x8000_0000 | UInt32(bitPattern: pid), pid: pid, appName: appName,
                       title: "No open windows", isHidden: isHidden, isWindowlessApp: true)
    }

    /// Windows seen in use come first, most recent first, because stacking order
    /// cannot compare windows on different Spaces. The rest keep their on-screen
    /// stacking order, with windows that have none (other Spaces, full screen,
    /// minimized, hidden) merged in by how recently their app was active.
    static func ordered(_ windows: [Self], frontmostPID: Int32?, focusedID: UInt32?, sameAppOnly: Bool,
                        frontToBack: [UInt32], recentPIDs: [Int32] = [], recentWindowIDs: [UInt32] = []) -> [Self] {
        let ranks = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let appRanks = Dictionary(recentPIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let usedRanks = Dictionary(recentWindowIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func appRank(_ window: Self) -> Int { window.pid == frontmostPID ? -1 : appRanks[window.pid] ?? Int.max }
        var seen: Set<UInt32> = []
        let everything = windows.filter { (!sameAppOnly || $0.pid == frontmostPID) && seen.insert($0.id).inserted }
        // Apps without windows form their own list after every window.
        let apps = everything.filter(\.isWindowlessApp).sorted { left, right in
            if appRank(left) != appRank(right) { return appRank(left) < appRank(right) }
            return left.appName.localizedStandardCompare(right.appName) == .orderedAscending
        }
        let candidates = everything.filter { !$0.isWindowlessApp }
        let used = candidates.filter { usedRanks[$0.id] != nil }.sorted { usedRanks[$0.id]! < usedRanks[$1.id]! }
        let unused = candidates.filter { usedRanks[$0.id] == nil }
        let onScreen = unused.filter { ranks[$0.id] != nil }.sorted { ranks[$0.id]! < ranks[$1.id]! }
        let offScreen = unused.filter { ranks[$0.id] == nil }.sorted { left, right in
            if appRank(left) != appRank(right) { return appRank(left) < appRank(right) }
            if left.pid != right.pid { return left.pid < right.pid }
            return left.id < right.id
        }
        var merged = used
        var (visible, rest) = (onScreen[...], offScreen[...])
        while let next = visible.first, let other = rest.first {
            if appRank(other) < appRank(next) { merged.append(rest.removeFirst()) }
            else { merged.append(visible.removeFirst()) }
        }
        merged += visible + rest
        if let focused = merged.firstIndex(where: { $0.id == focusedID }) {
            merged.insert(merged.remove(at: focused), at: 0)
        }
        return merged + apps
    }
}

/// Most recently used window first, as far as Switchboard has seen: the
/// window focused when the switcher opens, the window chosen in it, and the
/// focused window after an app activates or a Space changes.
struct WindowRecency {
    static let limit = 64
    private(set) var ids: [UInt32] = []

    mutating func used(_ id: UInt32) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }

    mutating func keep(only existing: Set<UInt32>) { ids.removeAll { !existing.contains($0) } }
}

/// Most recently activated app first.
struct ApplicationRecency {
    private(set) var pids: [Int32] = []

    mutating func activated(_ pid: Int32) {
        pids.removeAll { $0 == pid }
        pids.insert(pid, at: 0)
    }

    mutating func terminated(_ pid: Int32) { pids.removeAll { $0 == pid } }
}

/// Keystrokes can arrive before Accessibility has returned the window list.
/// Retain their net movement and the release so a quick tap still switches.
struct WindowSwitchingSession {
    private(set) var ids: [UInt32] = []
    private(set) var selectedIndex: Int?
    private(set) var isLoading = true
    private(set) var shouldCommit = false
    private var pendingSteps: Int

    init(backwards: Bool) { pendingSteps = backwards ? -1 : 1 }

    var selectedID: UInt32? { selectedIndex.map { ids[$0] } }

    mutating func load(_ ids: [UInt32], focusedID: UInt32?) {
        guard isLoading else { return }
        var seen: Set<UInt32> = []
        self.ids = ids.filter { seen.insert($0).inserted }
        isLoading = false
        guard !self.ids.isEmpty else { return }
        // Without a focused window, forward starts at the first entry.
        let start = focusedID.flatMap { self.ids.firstIndex(of: $0) } ?? (pendingSteps < 0 ? 0 : -1)
        selectedIndex = wrapped(start + pendingSteps)
        pendingSteps = 0
    }

    mutating func move(by offset: Int) {
        guard !shouldCommit else { return }
        if isLoading { pendingSteps += offset }
        else if let selectedIndex { self.selectedIndex = wrapped(selectedIndex + offset) }
    }

    mutating func select(_ id: UInt32) {
        guard !shouldCommit, let index = ids.firstIndex(of: id) else { return }
        selectedIndex = index
    }

    /// Like Command-Tab after quitting an app, the selection moves to the
    /// card that followed the removed one.
    mutating func remove(_ removed: Set<UInt32>) {
        let survivors = ids.filter { !removed.contains($0) }
        if let selectedIndex {
            let following = ids[selectedIndex...] + ids[..<selectedIndex]
            let next = following.first { !removed.contains($0) }
            self.selectedIndex = next.flatMap { survivors.firstIndex(of: $0) }
        }
        ids = survivors
    }

    mutating func release() { shouldCommit = true }

    private func wrapped(_ index: Int) -> Int { ((index % ids.count) + ids.count) % ids.count }
}

/// Windows on Spaces that are not showing, as remote lookup has learned them,
/// kept between openings so each window costs one scan at most.
struct HiddenWindowMemory<Element> {
    private var elements: [UInt32: Element] = [:]
    /// Window IDs a scan has already looked for. Some never answer (browser
    /// helper windows), and rescanning for them would spend the whole budget
    /// on every opening.
    private var searched: Set<UInt32> = []

    func element(for id: UInt32) -> Element? { elements[id] }

    mutating func remember(_ element: Element, for id: UInt32) {
        elements[id] = element
        searched.remove(id)
    }

    mutating func forget(_ id: UInt32) { elements[id] = nil }

    func unsearched(_ ids: Set<UInt32>) -> Set<UInt32> {
        ids.filter { elements[$0] == nil && !searched.contains($0) }
    }

    mutating func markSearched(_ ids: Set<UInt32>) { searched.formUnion(ids) }

    mutating func keep(only existing: Set<UInt32>) {
        elements = elements.filter { existing.contains($0.key) }
        searched.formIntersection(existing)
    }

    mutating func removeAll() {
        elements.removeAll()
        searched.removeAll()
    }
}

/// Apps number Accessibility elements as clients ask for them, so a
/// long-running app's newer windows sit far above its first ones. A scan
/// stops after a stretch of numbers past the newest element with no answer.
enum ElementScan {
    /// Chrome's largest gap between live elements was 231 on macOS 27.
    static let quietIDsBeforeStop: UInt64 = 1000

    static func isPastNewestElement(_ elementID: UInt64, newestLiveID: UInt64?) -> Bool {
        elementID > (newestLiveID ?? 0) + quietIDsBeforeStop
    }
}
