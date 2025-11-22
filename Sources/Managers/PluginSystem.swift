import Foundation
import RealityKit
import Metal
import AVFAudio

/// Extensible plugin system for custom rendering passes, ECS systems, and processors
@MainActor
class PluginSystem: ObservableObject {

    // MARK: - Plugin Types

    protocol Plugin {
        var id: UUID { get }
        var name: String { get }
        var version: String { get }

        func initialize() async throws
        func shutdown() async throws
    }

    protocol RenderPlugin: Plugin {
        func render(commandBuffer: MTLCommandBuffer, view: ARView) async
    }

    protocol ECSSystemPlugin: Plugin {
        func update(deltaTime: TimeInterval) async
    }

    protocol AudioProcessorPlugin: Plugin {
        func process(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer
    }

    // MARK: - Published Properties

    @Published var loadedPlugins: [String: any Plugin] = [:]
    @Published var pluginCount: Int = 0

    // MARK: - Plugin Registry

    private var renderPlugins: [any RenderPlugin] = []
    private var ecsPlugins: [any ECSSystemPlugin] = []
    private var audioPlugins: [any AudioProcessorPlugin] = []

    // MARK: - Plugin Loading

    private let pluginsDirectory: URL

    // MARK: - Statistics

    private(set) var pluginsLoaded: Int = 0
    private(set) var pluginErrors: Int = 0

    // MARK: - Initialization

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        pluginsDirectory = documentsPath.appendingPathComponent("Plugins")

        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

        print("✅ Plugin System initialized")
    }

    // MARK: - Plugin Registration

    /// Register custom rendering pass plugin
    func registerRenderPlugin(_ plugin: any RenderPlugin) async throws {
        try await plugin.initialize()

        renderPlugins.append(plugin)
        loadedPlugins[plugin.id.uuidString] = plugin
        pluginCount = loadedPlugins.count
        pluginsLoaded += 1

        print("✅ Registered render plugin: \(plugin.name) v\(plugin.version)")
    }

    /// Register ECS system plugin
    func registerECSPlugin(_ plugin: any ECSSystemPlugin) async throws {
        try await plugin.initialize()

        ecsPlugins.append(plugin)
        loadedPlugins[plugin.id.uuidString] = plugin
        pluginCount = loadedPlugins.count
        pluginsLoaded += 1

        print("✅ Registered ECS plugin: \(plugin.name) v\(plugin.version)")
    }

    /// Register audio processor plugin
    func registerAudioPlugin(_ plugin: any AudioProcessorPlugin) async throws {
        try await plugin.initialize()

        audioPlugins.append(plugin)
        loadedPlugins[plugin.id.uuidString] = plugin
        pluginCount = loadedPlugins.count
        pluginsLoaded += 1

        print("✅ Registered audio plugin: \(plugin.name) v\(plugin.version)")
    }

    // MARK: - Plugin Execution

    /// Execute all render plugins
    func executeRenderPlugins(commandBuffer: MTLCommandBuffer, view: ARView) async {
        for plugin in renderPlugins {
            await plugin.render(commandBuffer: commandBuffer, view: view)
        }
    }

    /// Execute all ECS system plugins
    func executeECSPlugins(deltaTime: TimeInterval) async {
        for plugin in ecsPlugins {
            await plugin.update(deltaTime: deltaTime)
        }
    }

    /// Process audio through audio plugins
    func processAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        var processedBuffer = buffer

        for plugin in audioPlugins {
            processedBuffer = plugin.process(buffer: processedBuffer)
        }

        return processedBuffer
    }

    // MARK: - Plugin Management

    /// Unregister plugin
    func unregisterPlugin(id: UUID) async throws {
        guard let plugin = loadedPlugins[id.uuidString] else {
            throw PluginError.pluginNotFound
        }

        try await plugin.shutdown()

        loadedPlugins.removeValue(forKey: id.uuidString)
        pluginCount = loadedPlugins.count

        // Remove from specific lists
        renderPlugins.removeAll { $0.id == id }
        ecsPlugins.removeAll { $0.id == id }
        audioPlugins.removeAll { $0.id == id }

        print("Unregistered plugin: \(plugin.name)")
    }

    /// Unregister all plugins
    func unregisterAll() async throws {
        for plugin in loadedPlugins.values {
            try await plugin.shutdown()
        }

        loadedPlugins.removeAll()
        renderPlugins.removeAll()
        ecsPlugins.removeAll()
        audioPlugins.removeAll()
        pluginCount = 0

        print("All plugins unregistered")
    }

    // MARK: - Plugin Discovery

    /// Get plugin by ID
    func getPlugin(id: UUID) -> (any Plugin)? {
        return loadedPlugins[id.uuidString]
    }

    /// Get all plugins of specific type
    func getRenderPlugins() -> [any RenderPlugin] {
        return renderPlugins
    }

    func getECSPlugins() -> [any ECSSystemPlugin] {
        return ecsPlugins
    }

    func getAudioPlugins() -> [any AudioProcessorPlugin] {
        return audioPlugins
    }

    // MARK: - Statistics

    func getPluginStats() -> PluginStats {
        return PluginStats(
            totalPlugins: pluginCount,
            renderPlugins: renderPlugins.count,
            ecsPlugins: ecsPlugins.count,
            audioPlugins: audioPlugins.count,
            pluginsLoaded: pluginsLoaded,
            pluginErrors: pluginErrors
        )
    }

    func getDebugInfo() -> String {
        let stats = getPluginStats()

        var info = "=== Plugin System ===\n"
        info += "Total Plugins: \(stats.totalPlugins)\n"
        info += "Render Plugins: \(stats.renderPlugins)\n"
        info += "ECS Plugins: \(stats.ecsPlugins)\n"
        info += "Audio Plugins: \(stats.audioPlugins)\n"
        info += "Plugins Loaded: \(stats.pluginsLoaded)\n"
        info += "Errors: \(stats.pluginErrors)\n"

        if !loadedPlugins.isEmpty {
            info += "\nLoaded Plugins:\n"
            for plugin in loadedPlugins.values {
                info += "  • \(plugin.name) v\(plugin.version)\n"
            }
        }

        info += "==================="

        return info
    }
}

// MARK: - Example Plugins

/// Example custom render pass plugin
class CustomBloomPlugin: RenderPlugin {
    let id = UUID()
    let name = "Custom Bloom"
    let version = "1.0.0"

    var intensity: Float = 1.0

    func initialize() async throws {
        print("Bloom plugin initialized")
    }

    func shutdown() async throws {
        print("Bloom plugin shutdown")
    }

    func render(commandBuffer: MTLCommandBuffer, view: ARView) async {
        // Custom bloom rendering pass would go here
    }
}

/// Example ECS system plugin
class CustomPhysicsPlugin: ECSSystemPlugin {
    let id = UUID()
    let name = "Custom Physics"
    let version = "1.0.0"

    func initialize() async throws {
        print("Physics plugin initialized")
    }

    func shutdown() async throws {
        print("Physics plugin shutdown")
    }

    func update(deltaTime: TimeInterval) async {
        // Custom physics update logic would go here
    }
}

/// Example audio processor plugin
class CustomReverbPlugin: AudioProcessorPlugin {
    let id = UUID()
    let name = "Custom Reverb"
    let version = "1.0.0"

    var reverbAmount: Float = 0.5

    func initialize() async throws {
        print("Reverb plugin initialized")
    }

    func shutdown() async throws {
        print("Reverb plugin shutdown")
    }

    func process(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Custom audio processing would go here
        return buffer
    }
}

// MARK: - Supporting Types

struct PluginStats {
    let totalPlugins: Int
    let renderPlugins: Int
    let ecsPlugins: Int
    let audioPlugins: Int
    let pluginsLoaded: Int
    let pluginErrors: Int
}

enum PluginError: Error {
    case pluginNotFound
    case initializationFailed
    case invalidPlugin
}
