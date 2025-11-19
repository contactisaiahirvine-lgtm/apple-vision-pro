import Foundation
import ARKit
import RealityKit
import simd
import Combine

/// Manages spatial persistence with save/load of world setups and cloud sync
@MainActor
class SpatialPersistenceManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var cloudSyncEnabled = false
    @Published var savedWorldsCount: Int = 0

    // MARK: - Persistence Data

    struct SavedWorld: Codable, Identifiable {
        let id: UUID
        let name: String
        let timestamp: Date
        let anchors: [SavedAnchor]
        let worldMap: Data?  // Serialized ARWorldMap
        let metadata: [String: String]

        init(id: UUID = UUID(), name: String, anchors: [SavedAnchor], worldMap: Data? = nil, metadata: [String: String] = [:]) {
            self.id = id
            self.name = name
            self.timestamp = Date()
            self.anchors = anchors
            self.worldMap = worldMap
            self.metadata = metadata
        }
    }

    struct SavedAnchor: Codable, Identifiable {
        let id: UUID
        let name: String
        let transform: TransformData
        let type: AnchorType
        let metadata: [String: String]

        enum AnchorType: String, Codable {
            case plane
            case image
            case object
            case face
            case body
            case custom
        }
    }

    struct TransformData: Codable {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let scale: SIMD3<Float>

        init(from transform: Transform) {
            self.position = transform.translation
            self.rotation = transform.rotation
            self.scale = transform.scale
        }

        func toTransform() -> Transform {
            return Transform(
                scale: scale,
                rotation: rotation,
                translation: position
            )
        }
    }

    // MARK: - Storage

    private var savedWorlds: [UUID: SavedWorld] = [:]
    private var currentWorldID: UUID?

    private let persistenceURL: URL
    private let worldMapsDirectory: URL

    // MARK: - Cloud Sync

    private var cloudSyncQueue: [SavedWorld] = []
    private var isSyncing = false

    // MARK: - AR Session

    private weak var arView: ARView?

    // MARK: - Statistics

    private(set) var worldsSaved: Int = 0
    private(set) var worldsLoaded: Int = 0
    private(set) var anchorsRestored: Int = 0

    // MARK: - Initialization

    init() {
        // Setup storage directories
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        persistenceURL = documentsPath.appendingPathComponent("SpatialPersistence")
        worldMapsDirectory = persistenceURL.appendingPathComponent("WorldMaps")

        // Create directories if needed
        try? FileManager.default.createDirectory(at: persistenceURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: worldMapsDirectory, withIntermediateDirectories: true)

        loadSavedWorlds()

        print("✅ Spatial Persistence Manager initialized (\(savedWorlds.count) worlds)")
    }

    // MARK: - Setup

    func setup(arView: ARView) {
        self.arView = arView
        print("Spatial persistence linked to ARView")
    }

    // MARK: - Save World

    /// Save current AR world setup
    func saveCurrentWorld(name: String, includeWorldMap: Bool = true) async throws {
        guard let arView = arView else {
            throw PersistenceError.arViewNotSet
        }

        print("Saving world: \(name)...")

        // Collect all anchors
        var savedAnchors: [SavedAnchor] = []

        for anchor in arView.session.currentFrame?.anchors ?? [] {
            let anchorType: SavedAnchor.AnchorType

            if anchor is ARPlaneAnchor {
                anchorType = .plane
            } else if anchor is ARImageAnchor {
                anchorType = .image
            } else {
                anchorType = .custom
            }

            let transform = Transform(matrix: anchor.transform)

            let savedAnchor = SavedAnchor(
                id: anchor.identifier,
                name: anchor.name ?? "Unnamed",
                transform: TransformData(from: transform),
                type: anchorType,
                metadata: [:]
            )

            savedAnchors.append(savedAnchor)
        }

        // Get world map if requested
        var worldMapData: Data? = nil

        if includeWorldMap {
            worldMapData = try await captureWorldMap(from: arView)
        }

        // Create saved world
        let savedWorld = SavedWorld(
            name: name,
            anchors: savedAnchors,
            worldMap: worldMapData
        )

        // Store
        savedWorlds[savedWorld.id] = savedWorld
        currentWorldID = savedWorld.id
        savedWorldsCount = savedWorlds.count
        worldsSaved += 1

        // Persist to disk
        try saveWorldToDisk(savedWorld)

        // Queue for cloud sync if enabled
        if cloudSyncEnabled {
            queueForCloudSync(savedWorld)
        }

        print("✅ World saved: \(name) (\(savedAnchors.count) anchors)")

        NotificationCenter.default.post(name: .worldSaved, object: savedWorld)
    }

    private func captureWorldMap(from arView: ARView) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            arView.session.getCurrentWorldMap { worldMap, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let worldMap = worldMap else {
                    continuation.resume(throwing: PersistenceError.worldMapCaptureFailed)
                    return
                }

                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Load World

    /// Load saved world and restore anchors
    func loadWorld(id: UUID) async throws {
        guard let savedWorld = savedWorlds[id] else {
            throw PersistenceError.worldNotFound
        }

        guard let arView = arView else {
            throw PersistenceError.arViewNotSet
        }

        print("Loading world: \(savedWorld.name)...")

        // Load world map if available
        if let worldMapData = savedWorld.worldMap {
            try await loadWorldMap(worldMapData, into: arView)
        }

        // Restore anchors
        var restoredCount = 0

        for savedAnchor in savedWorld.anchors {
            let transform = savedAnchor.transform.toTransform()
            let anchor = ARAnchor(name: savedAnchor.name, transform: transform.matrix)

            arView.session.add(anchor: anchor)
            restoredCount += 1
        }

        currentWorldID = id
        worldsLoaded += 1
        anchorsRestored += restoredCount

        print("✅ World loaded: \(savedWorld.name) (\(restoredCount) anchors)")

        NotificationCenter.default.post(name: .worldLoaded, object: savedWorld)
    }

    private func loadWorldMap(_ data: Data, into arView: ARView) async throws {
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw PersistenceError.worldMapDecodeFailed
        }

        // Create configuration with world map
        let configuration = ARWorldTrackingConfiguration()
        configuration.initialWorldMap = worldMap

        arView.session.run(configuration)
    }

    /// Load world by name
    func loadWorld(named name: String) async throws {
        guard let world = savedWorlds.values.first(where: { $0.name == name }) else {
            throw PersistenceError.worldNotFound
        }

        try await loadWorld(id: world.id)
    }

    // MARK: - Disk Persistence

    private func saveWorldToDisk(_ world: SavedWorld) throws {
        let fileURL = persistenceURL.appendingPathComponent("\(world.id.uuidString).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(world)

        try data.write(to: fileURL)

        print("World saved to disk: \(fileURL.lastPathComponent)")
    }

    private func loadSavedWorlds() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: persistenceURL, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let world = try decoder.decode(SavedWorld.self, from: data)
                savedWorlds[world.id] = world
            } catch {
                print("WARNING: Failed to load world from \(file.lastPathComponent): \(error)")
            }
        }

        savedWorldsCount = savedWorlds.count
    }

    // MARK: - Cloud Sync

    private func queueForCloudSync(_ world: SavedWorld) {
        cloudSyncQueue.append(world)

        if !isSyncing {
            Task {
                await performCloudSync()
            }
        }
    }

    private func performCloudSync() async {
        guard cloudSyncEnabled, !cloudSyncQueue.isEmpty else { return }

        isSyncing = true

        // In a real implementation, this would sync to iCloud or other cloud storage
        // For now, this is a placeholder

        print("Cloud sync: \(cloudSyncQueue.count) worlds")

        cloudSyncQueue.removeAll()
        isSyncing = false
    }

    /// Enable/disable cloud sync
    func setCloudSync(_ enabled: Bool) {
        cloudSyncEnabled = enabled
        print("Cloud sync: \(enabled)")

        if enabled {
            Task {
                await performCloudSync()
            }
        }
    }

    // MARK: - Management

    /// Get all saved worlds
    func getAllWorlds() -> [SavedWorld] {
        return Array(savedWorlds.values).sorted { $0.timestamp > $1.timestamp }
    }

    /// Delete saved world
    func deleteWorld(id: UUID) throws {
        guard let world = savedWorlds[id] else {
            throw PersistenceError.worldNotFound
        }

        // Delete from disk
        let fileURL = persistenceURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)

        // Remove from memory
        savedWorlds.removeValue(forKey: id)
        savedWorldsCount = savedWorlds.count

        print("World deleted: \(world.name)")

        NotificationCenter.default.post(name: .worldDeleted, object: world)
    }

    /// Clear all saved worlds
    func clearAllWorlds() throws {
        for id in savedWorlds.keys {
            try deleteWorld(id: id)
        }

        print("All worlds cleared")
    }

    // MARK: - Statistics

    func getPersistenceStats() -> PersistenceStats {
        let totalAnchors = savedWorlds.values.reduce(0) { $0 + $1.anchors.count }
        let totalSize = calculateTotalStorageSize()

        return PersistenceStats(
            savedWorldsCount: savedWorlds.count,
            worldsSaved: worldsSaved,
            worldsLoaded: worldsLoaded,
            anchorsRestored: anchorsRestored,
            totalAnchors: totalAnchors,
            totalStorageSize: totalSize,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncPending: cloudSyncQueue.count
        )
    }

    private func calculateTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0

        if let files = try? FileManager.default.contentsOfDirectory(at: persistenceURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resources.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        let stats = getPersistenceStats()

        var info = "=== Spatial Persistence ===\n"
        info += "Status: \(isEnabled ? "Enabled" : "Disabled")\n"
        info += "Saved Worlds: \(stats.savedWorldsCount)\n"
        info += "Total Anchors: \(stats.totalAnchors)\n"
        info += "Storage Size: \(ByteCountFormatter.string(fromByteCount: stats.totalStorageSize, countStyle: .file))\n"
        info += "Worlds Saved: \(stats.worldsSaved)\n"
        info += "Worlds Loaded: \(stats.worldsLoaded)\n"
        info += "Anchors Restored: \(stats.anchorsRestored)\n"
        info += "Cloud Sync: \(stats.cloudSyncEnabled ? "Enabled" : "Disabled")\n"
        if stats.cloudSyncPending > 0 {
            info += "Pending Sync: \(stats.cloudSyncPending)\n"
        }
        info += "======================="

        return info
    }
}

// MARK: - Supporting Types

struct PersistenceStats {
    let savedWorldsCount: Int
    let worldsSaved: Int
    let worldsLoaded: Int
    let anchorsRestored: Int
    let totalAnchors: Int
    let totalStorageSize: Int64
    let cloudSyncEnabled: Bool
    let cloudSyncPending: Int
}

enum PersistenceError: Error {
    case arViewNotSet
    case worldNotFound
    case worldMapCaptureFailed
    case worldMapDecodeFailed
}

// MARK: - Notifications

extension Notification.Name {
    static let worldSaved = Notification.Name("worldSaved")
    static let worldLoaded = Notification.Name("worldLoaded")
    static let worldDeleted = Notification.Name("worldDeleted")
}
