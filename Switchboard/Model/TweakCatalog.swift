import Foundation

enum TweakCatalog {
    static let all: [Tweak] = everyday + files + capture + dock

    static let everyday: [Tweak] = [
        Tweak(id: "everyday.keep-awake", title: "Keep Mac awake",
              subtitle: "Prevents display and idle sleep while Switchboard runs",
              category: .everyday, symbol: "cup.and.saucer.fill",
              control: .toggle, behavior: .keepAwake),
        Tweak(id: "everyday.close-windows", title: "Close windows when quitting apps",
              subtitle: "Stops old windows reopening the next time an app launches",
              category: .everyday, symbol: "macwindow",
              domain: "NSGlobalDomain", key: "NSQuitAlwaysKeepsWindows",
              onValue: .bool(false), offValue: .bool(true),
              successMessage: "Saved. Reopen apps to see the change."),
        Tweak(id: "everyday.scrollbars", title: "Show scroll bars",
              category: .everyday, symbol: "scroll",
              domain: "NSGlobalDomain", key: "AppleShowScrollBars",
              onValue: .string("Automatic"),
              control: .choice([
                  Choice(label: "Automatic", value: .string("Automatic")),
                  Choice(label: "Always", value: .string("Always")),
                  Choice(label: "When scrolling", value: .string("WhenScrolling"))
              ]), successMessage: "Saved. Reopen apps that do not update immediately."),
        Tweak(id: "everyday.plain-clipboard", title: "Strip clipboard formatting",
              subtitle: "Keeps the copied text and removes fonts, colours and links",
              category: .everyday, symbol: "doc.on.clipboard",
              control: .button("Make Plain"), behavior: .plainTextClipboard)
    ]

    static let files: [Tweak] = [
        Tweak(id: "files.hidden", title: "Show hidden files",
              category: .files, symbol: "eye",
              domain: "com.apple.finder", key: "AppleShowAllFiles",
              onValue: .bool(true), offValue: .bool(false), restart: .finder),
        Tweak(id: "files.extensions", title: "Show all filename extensions",
              category: .files, symbol: "doc.badge.ellipsis",
              domain: "NSGlobalDomain", key: "AppleShowAllExtensions",
              onValue: .bool(true), offValue: .bool(false), restart: .finder),
        Tweak(id: "files.full-path", title: "Show full path in Finder title",
              category: .files, symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
              domain: "com.apple.finder", key: "_FXShowPosixPathInTitle",
              onValue: .bool(true), offValue: .bool(false), restart: .finder),
        Tweak(id: "files.folders-first", title: "Keep folders on top",
              subtitle: "When Finder windows are sorted by name",
              category: .files, symbol: "folder.fill.badge.plus",
              domain: "com.apple.finder", key: "_FXSortFoldersFirst",
              onValue: .bool(true), offValue: .bool(false), restart: .finder),
        Tweak(id: "files.search-current", title: "Search the current folder",
              subtitle: "Uses the open folder instead of searching the whole Mac",
              category: .files, symbol: "magnifyingglass",
              domain: "com.apple.finder", key: "FXDefaultSearchScope",
              onValue: .string("SCcf"), restart: .finder),
        Tweak(id: "files.extension-warning", title: "Skip filename extension warnings",
              subtitle: "Stops Finder asking every time an extension changes",
              category: .files, symbol: "exclamationmark.bubble",
              domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning",
              onValue: .bool(false), offValue: .bool(true), restart: .finder),
        Tweak(id: "files.desktop-icons", title: "Hide desktop icons",
              subtitle: "Files stay in Desktop but no longer cover the wallpaper",
              category: .files, symbol: "rectangle.slash",
              domain: "com.apple.finder", key: "CreateDesktop",
              onValue: .bool(false), offValue: .bool(true), restart: .finder),
        Tweak(id: "files.network-stores", title: "Stop .DS_Store on network drives",
              subtitle: "Takes effect the next time the drive is mounted",
              category: .files, symbol: "externaldrive.connected.to.line.below",
              domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores",
              onValue: .bool(true), offValue: .bool(false),
              successMessage: "Saved. This applies the next time a network drive is mounted.")
    ]

    static let capture: [Tweak] = [
        Tweak(id: "capture.location", title: "Save screenshots to",
              category: .capture, symbol: "folder",
              domain: "com.apple.screencapture", key: "location",
              onValue: .string(NSHomeDirectory() + "/Desktop"),
              restart: .systemUIServer, control: .folder),
        Tweak(id: "capture.format", title: "Screenshot format",
              category: .capture, symbol: "photo",
              domain: "com.apple.screencapture", key: "type",
              onValue: .string("png"), restart: .systemUIServer,
              control: .choice([
                  Choice(label: "PNG", value: .string("png")),
                  Choice(label: "JPEG", value: .string("jpg")),
                  Choice(label: "HEIC", value: .string("heic"))
              ])),
        Tweak(id: "capture.thumbnail", title: "Skip the floating thumbnail",
              subtitle: "Saves screenshots immediately",
              category: .capture, symbol: "rectangle.on.rectangle.slash",
              domain: "com.apple.screencapture", key: "show-thumbnail",
              onValue: .bool(false), offValue: .bool(true), restart: .systemUIServer),
        Tweak(id: "capture.shadow", title: "Remove window shadows",
              category: .capture, symbol: "square.dashed",
              domain: "com.apple.screencapture", key: "disable-shadow",
              onValue: .bool(true), offValue: .bool(false), restart: .systemUIServer)
    ]

    static let dock: [Tweak] = [
        Tweak(id: "dock.instant-reveal", title: "Reveal a hidden Dock instantly",
              subtitle: "Only applies when Dock auto-hide is enabled",
              category: .dock, symbol: "dock.arrow.up.rectangle",
              domain: "com.apple.dock", key: "autohide-delay",
              onValue: .float(0), restart: .dock),
        Tweak(id: "dock.hide-recents", title: "Hide recent apps",
              category: .dock, symbol: "clock.arrow.circlepath",
              domain: "com.apple.dock", key: "show-recents",
              onValue: .bool(false), offValue: .bool(true), restart: .dock),
        Tweak(id: "dock.minimize-to-app", title: "Minimise windows into app icons",
              subtitle: "Keeps the right side of the Dock from filling up",
              category: .dock, symbol: "arrow.down.right.and.arrow.up.left",
              domain: "com.apple.dock", key: "minimize-to-application",
              onValue: .bool(true), offValue: .bool(false), restart: .dock)
    ]
}
