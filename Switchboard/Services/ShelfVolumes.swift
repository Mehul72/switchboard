import AppKit
import Combine
import Darwin
import OSLog

struct ShelfVolume: Identifiable, Equatable {
    let url: URL
    let name: String
    let uuid: String
    var imageURL: URL?
    /// The image's own whole disk, such as `/dev/disk10`. Detaching it is what
    /// Finder's eject does; ejecting the volume's disk can leave an APFS image attached.
    var imageDevice: String?

    var id: String { url.path + ":" + uuid }
    var subtitle: String { imageURL == nil ? "External drive" : "Disk image" }
    var symbol: String { imageURL == nil ? "externaldrive.fill" : "opticaldiscdrive.fill" }

    static func canEject(isInternal: Bool?, isEjectable: Bool?, isRemovable: Bool?,
                         isLocal: Bool?, isBrowsable: Bool?, path: String) -> Bool {
        // Hidden mounts belong to tools such as Xcode's Simulator runtimes; ejecting them breaks those tools.
        guard path != "/", !path.hasPrefix("/System/"), isLocal == true, isBrowsable == true else { return false }
        return isEjectable == true || isRemovable == true || isInternal == false
    }
}

struct ShelfDrop {
    let files: [URL]
    let volumes: [ShelfVolume]

    init(urls: [URL], volumes mounted: [ShelfVolume]) {
        var files: [URL] = []
        var volumes: [ShelfVolume] = []
        for url in urls where FileShelf.isLocalFile(url) {
            let normalized = url.standardizedFileURL
            if let volume = mounted.first(where: { $0.url.standardizedFileURL == normalized }) {
                if !volumes.contains(volume) { volumes.append(volume) }
            } else if !files.contains(normalized) {
                files.append(normalized)
            }
        }
        self.files = files
        self.volumes = volumes
    }
}

struct DiskImageMount: Equatable {
    let source: URL
    let device: String
}

enum DiskImageMounts {
    private static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
    private static let diskutil = URL(fileURLWithPath: "/usr/sbin/diskutil")

    static func parse(_ data: Data) throws -> [URL: DiskImageMount] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var mounts: [URL: DiskImageMount] = [:]
        for image in images {
            guard let path = image["image-path"] as? String, path.hasPrefix("/"),
                  let entities = image["system-entities"] as? [[String: Any]],
                  let device = entities.compactMap({ $0["dev-entry"] as? String }).first(where: isWholeDisk) else { continue }
            for entity in entities {
                guard let mount = entity["mount-point"] as? String, mount.hasPrefix("/"), mount != "/" else { continue }
                mounts[URL(fileURLWithPath: mount).standardizedFileURL] =
                    DiskImageMount(source: URL(fileURLWithPath: path).standardizedFileURL, device: device)
            }
        }
        return mounts
    }

    /// Only a bare whole-disk node is passed to `hdiutil detach`.
    static func isWholeDisk(_ device: String) -> Bool {
        let prefix = "/dev/disk"
        guard device.hasPrefix(prefix) else { return false }
        let number = device.dropFirst(prefix.count)
        return !number.isEmpty && number.allSatisfy { ("0"..."9").contains($0) }
    }

    static func read() throws -> [URL: DiskImageMount] {
        try parse(run(hdiutil, ["info", "-plist"], timeoutSeconds: 5,
                      failure: "Disk image discovery did not finish. Try refreshing."))
    }

    /// Ejecting the whole disk detaches the image. It fails rather than forcing
    /// when a file on the image is open. `hdiutil detach` is deprecated for this.
    static func detach(_ device: String) throws {
        guard isWholeDisk(device) else { throw CocoaError(.fileNoSuchFile) }
        _ = try run(diskutil, ["eject", device], timeoutSeconds: 30,
                    failure: "The disk may be in use. Close files on it and try again.")
    }

    private static func run(_ tool: URL, _ arguments: [String], timeoutSeconds: Double, failure: String) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // A wedged disk must not hold the worker queue indefinitely.
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableRuntimeMismatch, userInfo: [NSLocalizedDescriptionKey: failure])
        }
        return data
    }
}

enum NativeShelfVolumes {
    static func list() throws -> [ShelfVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey,
                                        .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey,
                                        .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                               options: []) else {
            throw CocoaError(.fileReadUnknown)
        }
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard ShelfVolume.canEject(isInternal: values.volumeIsInternal, isEjectable: values.volumeIsEjectable,
                                        isRemovable: values.volumeIsRemovable, isLocal: values.volumeIsLocal,
                                        isBrowsable: values.volumeIsBrowsable,
                                        path: url.path) else { return nil }
            // Without an identity, a replacement drive at the same path cannot be distinguished.
            guard let uuid = values.volumeUUIDString else { return nil }
            return ShelfVolume(url: url.standardizedFileURL, name: values.volumeName ?? url.lastPathComponent,
                               uuid: uuid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func linkingImages(_ volumes: [ShelfVolume],
                              readImages: () throws -> [URL: DiskImageMount] = DiskImageMounts.read) -> [ShelfVolume] {
        // Image association is a label; drives must stay ejectable when hdiutil fails.
        let images: [URL: DiskImageMount]
        do {
            images = try readImages()
        } catch {
            Logger(subsystem: "com.Mehul72.switchboard", category: "shelf-volumes")
                .error("Disk image association failed: \(error.localizedDescription, privacy: .private)")
            return volumes
        }
        return volumes.map { volume in
            var linked = volume
            linked.imageURL = images[volume.url]?.source
            linked.imageDevice = images[volume.url]?.device
            return linked
        }
    }

    static func eject(_ volume: ShelfVolume) throws {
        guard try list().contains(where: { $0.id == volume.id }) else {
            throw CocoaError(.fileNoSuchFile,
                             userInfo: [NSLocalizedDescriptionKey: "This disk is no longer connected. Refresh and try again."])
        }
        guard let device = volume.imageDevice else {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            return
        }
        // Device numbers are reused, so confirm this disk still backs the same image.
        guard try DiskImageMounts.read()[volume.url] == DiskImageMount(source: volume.imageURL ?? volume.url, device: device) else {
            throw CocoaError(.fileNoSuchFile,
                             userInfo: [NSLocalizedDescriptionKey: "This disk image changed. Refresh and try again."])
        }
        try DiskImageMounts.detach(device)
    }
}

@MainActor
final class ShelfVolumes: ObservableObject {
    typealias Load = (@escaping (Result<[ShelfVolume], Error>) -> Void) -> Void
    typealias Eject = (ShelfVolume, @escaping (Result<Void, Error>) -> Void) -> Void
    @Published private(set) var volumes: [ShelfVolume] = []
    @Published private(set) var ejecting: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var notice: ShelfNotice?
    private let load: Load
    private let requestEject: Eject
    private var observers: [NSObjectProtocol] = []
    private var refreshAgain = false
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "shelf-volumes")

    init(load: @escaping Load, eject: @escaping Eject) {
        self.load = load
        self.requestEject = eject
    }

    convenience init() {
        let queue = DispatchQueue(label: "com.Mehul72.switchboard.shelf-volumes", qos: .userInitiated)
        self.init(load: { completion in
            queue.async {
                let result = Result { NativeShelfVolumes.linkingImages(try NativeShelfVolumes.list()) }
                DispatchQueue.main.async { completion(result) }
            }
        }, eject: { volume, completion in
            queue.async {
                let result = Result { try NativeShelfVolumes.eject(volume) }
                DispatchQueue.main.async { completion(result) }
            }
        })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        load { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            switch result {
            case .success(let volumes): self.volumes = volumes
            case .failure(let error):
                self.notice = ShelfNotice(text: "Could not refresh disks. \(error.localizedDescription)", isError: true)
                self.logger.error("Volume discovery failed: \(error.localizedDescription, privacy: .private)")
            }
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    /// `failed` runs only when macOS refused the eject, so a caller outside the
    /// shelf can show the reason. A duplicate or stale request calls nothing.
    func eject(_ volume: ShelfVolume, failed: (() -> Void)? = nil) {
        guard volumes.contains(where: { $0.id == volume.id }), ejecting.insert(volume.id).inserted else { return }
        notice = nil
        requestEject(volume) { [weak self] result in
            guard let self else { return }
            self.ejecting.remove(volume.id)
            switch result {
            case .success:
                self.volumes.removeAll { $0.id == volume.id }
                self.notice = ShelfNotice(text: "“\(volume.name)” ejected.")
                self.logger.info("Volume ejected successfully")
            case .failure(let error):
                self.notice = ShelfNotice(text: "Could not eject “\(volume.name)”. \(error.localizedDescription)", isError: true)
                self.logger.error("Eject failed: \(error.localizedDescription, privacy: .private)")
                failed?()
            }
            self.refresh()
        }
    }

    func mountedImages(for url: URL) -> [ShelfVolume] {
        let source = url.resolvingSymlinksInPath().standardizedFileURL
        return volumes.filter { $0.imageURL?.resolvingSymlinksInPath().standardizedFileURL == source }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }
}
