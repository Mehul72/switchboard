import Foundation

enum TweakCatalog {
    static let all: [Tweak] = everyday + files + capture + dock

    static let everyday: [Tweak] = [
        Tweak(id: "everyday.keep-awake", title: "Keep Mac awake",
              subtitle: "Blocks display and idle sleep",
              category: .everyday, symbol: "cup.and.saucer.fill",
              control: .choice([
                  Choice(label: "Off", value: .int(0)),
                  Choice(label: "30 minutes", value: .int(30)),
                  Choice(label: "1 hour", value: .int(60)),
                  Choice(label: "2 hours", value: .int(120)),
                  Choice(label: "Until I stop it", value: .int(AwakeController.indefinite))
              ]),
              behavior: .keepAwake),
        Tweak(id: "everyday.region-ocr", title: "Copy text from the screen",
              subtitle: "Drag a region to copy its text",
              category: .everyday, symbol: "text.viewfinder",
              control: .button("Select Area"), behavior: .regionOCR),
        // Translation is finished and verified but held back from the UI for
        // now. Re-enable by restoring this row and flipping
        // TweakStore.translationEnabled back to true.
        //
        // Tweak(id: "everyday.ocr-translate", title: "Translate to English",
        // subtitle: "Applies to text you capture above",
        // category: .everyday, symbol: "character.book.closed",
        // control: .toggle, behavior: .translateCaptures),
        Tweak(id: "everyday.quit-on-close", title: "Red button quits the app",
              subtitle: "Also quits when the last window closes",
              category: .everyday, symbol: "xmark.app",
              control: .toggle, behavior: .quitOnClose),
        Tweak(id: "everyday.scrollbars", title: "Show scroll bars",
              category: .everyday, symbol: "scroll",
              domain: "NSGlobalDomain", key: "AppleShowScrollBars",
              onValue: .string("Automatic"),
              control: .choice([
                  Choice(label: "Automatic", value: .string("Automatic")),
                  Choice(label: "Always", value: .string("Always")),
                  Choice(label: "When scrolling", value: .string("WhenScrolling"))
              ]), successMessage: "Saved. Reopen apps that do not update immediately."),
        Tweak(id: "everyday.mouse-scroll", title: "Traditional mouse scrolling",
              subtitle: "Trackpad keeps natural scrolling",
              category: .everyday, symbol: "computermouse",
              control: .toggle, behavior: .mouseScrollDirection),
        Tweak(id: "everyday.plain-clipboard", title: "Strip clipboard formatting",
              subtitle: "Removes fonts, colours and links",
              category: .everyday, symbol: "doc.on.clipboard",
              control: .button("Make Plain"), behavior: .plainTextClipboard)
    ]

    static let files: [Tweak] = [
        Tweak(id: "files.hidden", title: "Show hidden files",
              category: .files, symbol: "eye",
              domain: "com.apple.finder", key: "AppleShowAllFiles",
              onValue: .bool(true), offValue: .bool(false), restart: .finder),
        Tweak(id: "files.extensions", title: "Show all file extensions",
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
              subtitle: "Instead of searching the whole Mac",
              category: .files, symbol: "magnifyingglass",
              domain: "com.apple.finder", key: "FXDefaultSearchScope",
              onValue: .string("SCcf"), restart: .finder),
        Tweak(id: "files.extension-warning", title: "Skip extension warnings",
              subtitle: "No confirmation when an extension changes",
              category: .files, symbol: "exclamationmark.bubble",
              domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning",
              onValue: .bool(false), offValue: .bool(true), restart: .finder),
        Tweak(id: "files.desktop-icons", title: "Hide desktop icons",
              subtitle: "Files stay in the Desktop folder",
              category: .files, symbol: "rectangle.slash",
              domain: "com.apple.finder", key: "CreateDesktop",
              onValue: .bool(false), offValue: .bool(true), restart: .finder),
        Tweak(id: "files.network-stores", title: "No .DS_Store on network drives",
              subtitle: "Applies at the next mount",
              category: .files, symbol: "externaldrive.connected.to.line.below",
              domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores",
              onValue: .bool(true), offValue: .bool(false),
              successMessage: "Saved. This applies the next time a network drive is mounted.")
    ]

    // Screenshot settings are read by the capture subsystem at the moment a
    // screenshot is taken, so they need no restart -- the legacy
    // "killall SystemUIServer" step does nothing for them.
    static let capture: [Tweak] = [
        Tweak(id: "capture.location", title: "Save screenshots to",
              category: .capture, symbol: "folder",
              domain: "com.apple.screencapture", key: "location",
              onValue: .string(NSHomeDirectory() + "/Desktop"),
              control: .folder,
              successMessage: "Saved. Your next screenshot lands there."),
        Tweak(id: "capture.clipboard", title: "Copy screenshots to clipboard",
              subtitle: "No file is saved; encoding still applies",
              category: .capture, symbol: "doc.on.clipboard",
              domain: "com.apple.screencapture", key: "target",
              onValue: .string("clipboard"), offValue: .string("file"),
              successMessage: "Saved. Your next screenshot goes to the clipboard, ready to paste."),
        Tweak(id: "capture.format", title: "Screenshot format",
              subtitle: "Clipboard images are converted too",
              category: .capture, symbol: "photo",
              domain: "com.apple.screencapture", key: "type",
              onValue: .string("png"),
              control: .choice([
                  Choice(label: "PNG", value: .string("png")),
                  Choice(label: "JPEG", value: .string("jpg")),
                  Choice(label: "HEIC", value: .string("heic"))
              ]),
              successMessage: "Saved. New screenshots use that encoding where the destination supports it."),
        Tweak(id: "capture.thumbnail", title: "Skip the floating thumbnail",
              subtitle: "Saves screenshots immediately",
              category: .capture, symbol: "rectangle.on.rectangle.slash",
              domain: "com.apple.screencapture", key: "show-thumbnail",
              onValue: .bool(false), offValue: .bool(true),
              successMessage: "Saved. Applies to your next screenshot."),
        Tweak(id: "capture.shadow", title: "Remove window shadows",
              subtitle: "Window captures only",
              category: .capture, symbol: "square.dashed",
              domain: "com.apple.screencapture", key: "disable-shadow",
              onValue: .bool(true), offValue: .bool(false),
              successMessage: "Saved. Applies to your next window capture.")
    ]

    static let dock: [Tweak] = [
        Tweak(id: "dock.instant-reveal", title: "Reveal hidden Dock instantly",
              subtitle: "Needs the Dock set to hide",
              category: .dock, symbol: "dock.arrow.up.rectangle",
              domain: "com.apple.dock", key: "autohide-delay",
              onValue: .float(0), restart: .dock),
        Tweak(id: "dock.hide-recents", title: "Hide recent apps",
              category: .dock, symbol: "clock.arrow.circlepath",
              domain: "com.apple.dock", key: "show-recents",
              onValue: .bool(false), offValue: .bool(true), restart: .dock),
        Tweak(id: "dock.minimize-to-app", title: "Minimise into app icons",
              subtitle: "Keeps the Dock from filling up",
              category: .dock, symbol: "arrow.down.right.and.arrow.up.left",
              domain: "com.apple.dock", key: "minimize-to-application",
              onValue: .bool(true), offValue: .bool(false), restart: .dock)
    ]
}
