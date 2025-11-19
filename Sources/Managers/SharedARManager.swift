import Foundation
import ARKit
import RealityKit
import MultipeerConnectivity
import simd
import Combine

/// Manages shared AR experience with anchor and transform synchronization for multiplayer
@MainActor
class SharedARManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var isSharing = false
    @Published var participantCount: Int = 0
    @Published var syncMode: SyncMode = .authoritative

    // MARK: - Sync Configuration

    enum SyncMode {
        case authoritative  // Server decides physics/state
        case nonAuthoritative  // Client prediction
        case peerToPeer  // No central authority
    }

    // MARK: - Shared State

    struct SharedAnchor: Codable, Identifiable {
        let id: UUID
        let ownerID: UUID
        let transform: TransformData
        let timestamp: Date
        let anchorType: AnchorType

        enum AnchorType: String, Codable {
            case plane
            case image
            case object
            case custom
        }
    }

    struct TransformUpdate: Codable {
        let anchorID: UUID
        let transform: TransformData
        let velocity: SIMD3<Float>?
        let timestamp: Date
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

    // MARK: - Networking

    private weak var networkManager: NetworkManager?
    private var localParticipantID: UUID

    // MARK: - Anchor Tracking

    private var sharedAnchors: [UUID: SharedAnchor] = [:]
    private var anchorOwnership: [UUID: UUID] = [:]  // anchorID -> ownerID
    private var transformUpdates: [UUID: TransformUpdate] = [:]

    // MARK: - AR Integration

    private weak var arView: ARView?
    private var anchorEntities: [UUID: AnchorEntity] = [:]

    // MARK: - Physics Sync

    private var physicsAuthority: UUID?  // Who controls physics
    private var replicationRate: TimeInterval = 1.0 / 20.0  // 20 Hz default

    // MARK: - Statistics

    private(set) var anchorsSynced: Int = 0
    private(set) var transformsReceived: Int = 0
    private(set) var transformsSent: Int = 0
    private(set) var syncLatency: TimeInterval = 0

    // MARK: - Initialization

    init(localParticipantID: UUID = UUID()) {
        self.localParticipantID = localParticipantID
        print("✅ Shared AR Manager initialized (ID: \(localParticipantID.uuidString.prefix(8)))")
    }

    // MARK: - Setup

    func setup(arView: ARView, networkManager: NetworkManager) {
        self.arView = arView
        self.networkManager = networkManager

        setupNetworkListeners()

        print("Shared AR linked to ARView and NetworkManager")
    }

    private func setupNetworkListeners() {
        // Listen for incoming shared AR data
        NotificationCenter.default.publisher(for: .sharedAnchorReceived)
            .sink { [weak self] notification in
                if let anchorData = notification.userInfo?["anchor"] as? Data {
                    self?.handleSharedAnchor(anchorData)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .transformUpdateReceived)
            .sink { [weak self] notification in
                if let updateData = notification.userInfo?["transform"] as? Data {
                    self?.handleTransformUpdate(updateData)
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sharing Control

    /// Start sharing AR experience
    func startSharing() {
        guard let arView = arView else {
            print("ERROR: ARView not set")
            return
        }

        isSharing = true

        // Set as physics authority if authoritative mode
        if syncMode == .authoritative {
            physicsAuthority = localParticipantID
        }

        print("Started sharing AR experience (\(syncMode) mode)")
    }

    /// Stop sharing AR experience
    func stopSharing() {
        isSharing = false
        physicsAuthority = nil
        print("Stopped sharing AR experience")
    }

    // MARK: - Anchor Synchronization

    /// Share local anchor with other participants
    func shareAnchor(_ anchor: ARAnchor) {
        guard isSharing else { return }

        let transform = Transform(matrix: anchor.transform)
        let sharedAnchor = SharedAnchor(
            id: anchor.identifier,
            ownerID: localParticipantID,
            transform: TransformData(from: transform),
            timestamp: Date(),
            anchorType: .custom
        )

        // Store locally
        sharedAnchors[anchor.identifier] = sharedAnchor
        anchorOwnership[anchor.identifier] = localParticipantID

        // Send to network
        sendSharedAnchor(sharedAnchor)

        anchorsSynced += 1

        print("Shared anchor: \(anchor.identifier)")
    }

    /// Share plane anchor
    func sharePlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
        guard isSharing else { return }

        let transform = Transform(matrix: planeAnchor.transform)
        let sharedAnchor = SharedAnchor(
            id: planeAnchor.identifier,
            ownerID: localParticipantID,
            transform: TransformData(from: transform),
            timestamp: Date(),
            anchorType: .plane
        )

        sharedAnchors[planeAnchor.identifier] = sharedAnchor
        anchorOwnership[planeAnchor.identifier] = localParticipantID

        sendSharedAnchor(sharedAnchor)

        anchorsSynced += 1
    }

    private func sendSharedAnchor(_ anchor: SharedAnchor) {
        guard let data = try? JSONEncoder().encode(anchor) else { return }

        networkManager?.sendGameEvent(eventName: "sharedAnchor", data: data)
        print("Sent shared anchor: \(anchor.id.uuidString.prefix(8))")
    }

    private func handleSharedAnchor(_ data: Data) {
        guard let anchor = try? JSONDecoder().decode(SharedAnchor.self, from: data) else {
            print("ERROR: Failed to decode shared anchor")
            return
        }

        // Don't process our own anchors
        guard anchor.ownerID != localParticipantID else { return }

        // Store anchor
        sharedAnchors[anchor.id] = anchor
        anchorOwnership[anchor.id] = anchor.ownerID

        // Create AR anchor
        let transform = anchor.transform.toTransform()
        let arAnchor = ARAnchor(name: "Shared-\(anchor.id.uuidString.prefix(8))", transform: transform.matrix)

        arView?.session.add(anchor: arAnchor)

        anchorsSynced += 1

        print("Received shared anchor from \(anchor.ownerID.uuidString.prefix(8))")
    }

    // MARK: - Transform Replication

    /// Replicate entity transform to other participants
    func replicateTransform(anchorID: UUID, transform: Transform, velocity: SIMD3<Float>? = nil) {
        guard isSharing else { return }

        let update = TransformUpdate(
            anchorID: anchorID,
            transform: TransformData(from: transform),
            velocity: velocity,
            timestamp: Date()
        )

        transformUpdates[anchorID] = update

        // Send update
        if let data = try? JSONEncoder().encode(update) {
            networkManager?.sendGameEvent(eventName: "transformUpdate", data: data)
            transformsSent += 1
        }
    }

    private func handleTransformUpdate(_ data: Data) {
        guard let update = try? JSONDecoder().decode(TransformUpdate.self, from: data) else {
            print("ERROR: Failed to decode transform update")
            return
        }

        transformUpdates[update.anchorID] = update
        transformsReceived += 1

        // Calculate latency
        syncLatency = Date().timeIntervalSince(update.timestamp)

        // Apply transform to entity if we have it
        applyTransformUpdate(update)
    }

    private func applyTransformUpdate(_ update: TransformUpdate) {
        guard let anchorEntity = anchorEntities[update.anchorID] else { return }

        let transform = update.transform.toTransform()

        // Apply transform
        anchorEntity.transform = transform

        // Apply velocity if in non-authoritative mode
        if syncMode == .nonAuthoritative, let velocity = update.velocity {
            // Client-side prediction would use velocity here
        }
    }

    // MARK: - Physics Synchronization

    /// Check if local participant has physics authority
    func hasPhysicsAuthority() -> Bool {
        return physicsAuthority == localParticipantID
    }

    /// Request physics authority
    func requestPhysicsAuthority() {
        guard syncMode == .authoritative else {
            print("WARNING: Physics authority only applicable in authoritative mode")
            return
        }

        // Send request to current authority
        networkManager?.sendGameEvent(eventName: "requestPhysicsAuthority", data: Data())
    }

    /// Transfer physics authority to participant
    func transferPhysicsAuthority(to participantID: UUID) {
        guard hasPhysicsAuthority() else {
            print("WARNING: Cannot transfer physics authority - not current authority")
            return
        }

        physicsAuthority = participantID
        print("Physics authority transferred to \(participantID.uuidString.prefix(8))")

        // Notify all participants
        networkManager?.sendGameEvent(eventName: "physicsAuthorityChanged", data: participantID.uuidString.data(using: .utf8)!)
    }

    // MARK: - Update Loop

    /// Update shared AR (call from game loop)
    func update(deltaTime: TimeInterval) {
        guard isSharing else { return }

        // Replication is event-driven, no continuous updates needed
        // Could implement interpolation/prediction here
    }

    // MARK: - Configuration

    /// Set replication rate (updates per second)
    func setReplicationRate(_ rate: Double) {
        replicationRate = 1.0 / rate
        print("Replication rate: \(Int(rate)) Hz")
    }

    /// Set sync mode
    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode

        if mode == .authoritative && isSharing {
            physicsAuthority = localParticipantID
        }

        print("Sync mode: \(mode)")
    }

    // MARK: - Query

    /// Get all shared anchors
    func getSharedAnchors() -> [SharedAnchor] {
        return Array(sharedAnchors.values)
    }

    /// Get anchor owner
    func getAnchorOwner(_ anchorID: UUID) -> UUID? {
        return anchorOwnership[anchorID]
    }

    /// Check if anchor is locally owned
    func isLocalAnchor(_ anchorID: UUID) -> Bool {
        return anchorOwnership[anchorID] == localParticipantID
    }

    // MARK: - Statistics

    func getSharedARStats() -> SharedARStats {
        return SharedARStats(
            isSharing: isSharing,
            syncMode: syncMode,
            participantCount: participantCount,
            sharedAnchorsCount: sharedAnchors.count,
            anchorsSynced: anchorsSynced,
            transformsReceived: transformsReceived,
            transformsSent: transformsSent,
            syncLatency: syncLatency,
            hasPhysicsAuthority: hasPhysicsAuthority()
        )
    }

    func resetStats() {
        anchorsSynced = 0
        transformsReceived = 0
        transformsSent = 0
        syncLatency = 0
        print("Shared AR stats reset")
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        let stats = getSharedARStats()

        var info = "=== Shared AR ===\n"
        info += "Status: \(stats.isSharing ? "Sharing" : "Not Sharing")\n"
        info += "Sync Mode: \(stats.syncMode)\n"
        info += "Participants: \(stats.participantCount)\n"
        info += "Shared Anchors: \(stats.sharedAnchorsCount)\n"
        info += "Anchors Synced: \(stats.anchorsSynced)\n"
        info += "Transforms Sent: \(stats.transformsSent)\n"
        info += "Transforms Received: \(stats.transformsReceived)\n"
        info += "Sync Latency: \(String(format: "%.1f", stats.syncLatency * 1000))ms\n"
        info += "Physics Authority: \(stats.hasPhysicsAuthority ? "Yes" : "No")\n"
        info += "================"

        return info
    }
}

// MARK: - Supporting Types

struct SharedARStats {
    let isSharing: Bool
    let syncMode: SharedARManager.SyncMode
    let participantCount: Int
    let sharedAnchorsCount: Int
    let anchorsSynced: Int
    let transformsReceived: Int
    let transformsSent: Int
    let syncLatency: TimeInterval
    let hasPhysicsAuthority: Bool
}

// MARK: - Notifications

extension Notification.Name {
    static let sharedAnchorReceived = Notification.Name("sharedAnchorReceived")
    static let transformUpdateReceived = Notification.Name("transformUpdateReceived")
}
