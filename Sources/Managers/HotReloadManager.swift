import Foundation
import Metal

/// Hot-reload system for rapid iteration on shaders, systems, and assets
@MainActor
class HotReloadManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = false
    @Published var watchingFiles: Int = 0

    // MARK: - Watch Configuration

    private var watchedPaths: Set<String> = []
    private var fileTimestamps: [String: Date] = [:]

    // MARK: - Reload Handlers

    typealias ReloadHandler = (URL) async -> Void

    private var shaderReloadHandlers: [ReloadHandler] = []
    private var assetReloadHandlers: [ReloadHandler] = []
    private var systemReloadHandlers: [ReloadHandler] = []

    // MARK: - File Monitoring

    private var fileCheckTimer: Timer?
    private let checkInterval: TimeInterval = 1.0  // Check every second

    // MARK: - Metal Resources

    private weak var device: MTLDevice?
    private var shaderLibrary: MTLLibrary?

    // MARK: - Statistics

    private(set) var shadersReloaded: Int = 0
    private(set) var assetsReloaded: Int = 0
    private(set) var systemsReloaded: Int = 0
    private(set) var reloadErrors: Int = 0

    // MARK: - Initialization

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            self.shaderLibrary = device.makeDefaultLibrary()
        }

        print("✅ Hot-Reload Manager initialized")
    }

    deinit {
        fileCheckTimer?.invalidate()
        fileCheckTimer = nil
    }

    // MARK: - Watch Management

    /// Start watching files for changes
    func startWatching() {
        guard !isEnabled else { return }

        isEnabled = true

        // Start file check timer
        fileCheckTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForChanges()
            }
        }

        print("Started hot-reload file watching")
    }

    /// Stop watching files
    func stopWatching() {
        isEnabled = false
        fileCheckTimer?.invalidate()
        fileCheckTimer = nil
        print("Stopped hot-reload file watching")
    }

    /// Add path to watch list
    func watch(path: String) {
        watchedPaths.insert(path)
        watchingFiles = watchedPaths.count

        // Record initial timestamp
        if let url = URL(string: path),
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attributes[.modificationDate] as? Date {
            fileTimestamps[path] = modDate
        }

        print("Watching: \(path)")
    }

    /// Watch shader files in directory
    func watchShaders(in directory: String) {
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(atPath: directory) {
            for case let file as String in enumerator {
                if file.hasSuffix(".metal") {
                    watch(path: "\(directory)/\(file)")
                }
            }
        }
    }

    // MARK: - Change Detection

    private func checkForChanges() async {
        for path in watchedPaths {
            guard let url = URL(string: path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modDate = attributes[.modificationDate] as? Date else {
                continue
            }

            // Check if file changed
            if let lastDate = fileTimestamps[path], modDate > lastDate {
                fileTimestamps[path] = modDate
                await handleFileChange(url)
            }
        }
    }

    private func handleFileChange(_ url: URL) async {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "metal":
            await reloadShader(url)

        case "usdz", "usda", "reality":
            await reloadAsset(url)

        case "swift":
            // System reload (requires runtime Swift support)
            await reloadSystem(url)

        default:
            print("Unknown file type: \(ext)")
        }
    }

    // MARK: - Shader Reload

    private func reloadShader(_ url: URL) async {
        print("Reloading shader: \(url.lastPathComponent)")

        guard let device = device else {
            reloadErrors += 1
            return
        }

        do {
            // Compile shader
            let source = try String(contentsOf: url)
            let library = try device.makeLibrary(source: source, options: nil)

            shaderLibrary = library
            shadersReloaded += 1

            // Notify handlers
            for handler in shaderReloadHandlers {
                await handler(url)
            }

            print("✅ Shader reloaded: \(url.lastPathComponent)")

            NotificationCenter.default.post(
                name: .shaderReloaded,
                object: url
            )

        } catch {
            print("ERROR: Failed to reload shader: \(error)")
            reloadErrors += 1
        }
    }

    /// Register shader reload handler
    func onShaderReload(_ handler: @escaping ReloadHandler) {
        shaderReloadHandlers.append(handler)
    }

    // MARK: - Asset Reload

    private func reloadAsset(_ url: URL) async {
        print("Reloading asset: \(url.lastPathComponent)")

        // Notify handlers to reload asset
        for handler in assetReloadHandlers {
            await handler(url)
        }

        assetsReloaded += 1

        print("✅ Asset reloaded: \(url.lastPathComponent)")

        NotificationCenter.default.post(
            name: .assetReloaded,
            object: url
        )
    }

    /// Register asset reload handler
    func onAssetReload(_ handler: @escaping ReloadHandler) {
        assetReloadHandlers.append(handler)
    }

    // MARK: - System Reload

    private func reloadSystem(_ url: URL) async {
        print("Reloading system: \(url.lastPathComponent)")

        // System reload would require runtime Swift compilation
        // This is a placeholder for future implementation

        for handler in systemReloadHandlers {
            await handler(url)
        }

        systemsReloaded += 1

        print("✅ System reloaded: \(url.lastPathComponent)")

        NotificationCenter.default.post(
            name: .systemReloaded,
            object: url
        )
    }

    /// Register system reload handler
    func onSystemReload(_ handler: @escaping ReloadHandler) {
        systemReloadHandlers.append(handler)
    }

    // MARK: - Manual Reload

    /// Manually trigger shader reload
    func reloadAllShaders() async {
        for path in watchedPaths {
            if path.hasSuffix(".metal"), let url = URL(string: path) {
                await reloadShader(url)
            }
        }
    }

    /// Manually trigger asset reload
    func reloadAllAssets() async {
        for path in watchedPaths {
            let ext = URL(fileURLWithPath: path).pathExtension
            if ["usdz", "usda", "reality"].contains(ext), let url = URL(string: path) {
                await reloadAsset(url)
            }
        }
    }

    // MARK: - Statistics

    func getHotReloadStats() -> HotReloadStats {
        return HotReloadStats(
            isEnabled: isEnabled,
            watchingFiles: watchingFiles,
            shadersReloaded: shadersReloaded,
            assetsReloaded: assetsReloaded,
            systemsReloaded: systemsReloaded,
            reloadErrors: reloadErrors
        )
    }

    func getDebugInfo() -> String {
        let stats = getHotReloadStats()

        var info = "=== Hot-Reload System ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Watching: \(stats.watchingFiles) files\n"
        info += "Shaders Reloaded: \(stats.shadersReloaded)\n"
        info += "Assets Reloaded: \(stats.assetsReloaded)\n"
        info += "Systems Reloaded: \(stats.systemsReloaded)\n"
        info += "Errors: \(stats.reloadErrors)\n"
        info += "======================="

        return info
    }
}

struct HotReloadStats {
    let isEnabled: Bool
    let watchingFiles: Int
    let shadersReloaded: Int
    let assetsReloaded: Int
    let systemsReloaded: Int
    let reloadErrors: Int
}

extension Notification.Name {
    static let shaderReloaded = Notification.Name("shaderReloaded")
    static let assetReloaded = Notification.Name("assetReloaded")
    static let systemReloaded = Notification.Name("systemReloaded")
}
