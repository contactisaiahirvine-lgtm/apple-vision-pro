import Foundation
import RealityKit
import ARKit
import simd

/// Physics-based gaze targeting for improved selection confidence
@MainActor
class PhysicsGazeTargetingManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var currentTarget: Entity?
    @Published var gazeConfidence: Float = 0.0

    // MARK: - Configuration

    var raycastMaxDistance: Float = 100.0
    var selectionThreshold: Float = 0.8  // Confidence threshold
    var smoothingFactor: Float = 0.7  // Reduces jitter

    // MARK: - Gaze Tracking

    private var gazeHistory: [GazeHit] = []
    private let historySize = 10
    private var smoothedTarget: Entity?

    struct GazeHit {
        let entity: Entity?
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let distance: Float
        let timestamp: Date
        let confidence: Float
    }

    // MARK: - Physics Raycast

    private weak var arView: ARView?
    private var lastRaycastTime: TimeInterval = 0
    private let raycastInterval: TimeInterval = 1.0 / 60.0  // 60 Hz

    // MARK: - Statistics

    private(set) var raycasts: Int = 0
    private(set) var successfulHits: Int = 0
    private(set) var selections: Int = 0

    // MARK: - Initialization

    init() {
        print("✅ Physics-Based Gaze Targeting initialized")
    }

    // MARK: - Setup

    func setup(arView: ARView) {
        self.arView = arView
        print("Physics gaze targeting linked to ARView")
    }

    // MARK: - Gaze Update

    /// Update gaze targeting (call from game loop)
    func update(currentTime: TimeInterval) {
        guard isEnabled else { return }

        if currentTime - lastRaycastTime >= raycastInterval {
            performPhysicsRaycast()
            lastRaycastTime = currentTime
        }
    }

    private func performPhysicsRaycast() {
        guard let arView = arView,
              let frame = arView.session.currentFrame else {
            return
        }

        // Get camera transform
        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // Forward direction
        let forward = SIMD3<Float>(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        )

        // Perform physics raycast
        let raycastResult = performRaycast(
            origin: cameraPosition,
            direction: forward
        )

        raycasts += 1

        // Add to history
        if gazeHistory.count >= historySize {
            gazeHistory.removeFirst()
        }
        gazeHistory.append(raycastResult)

        // Update smoothed target
        updateSmoothedTarget()
    }

    private func performRaycast(origin: SIMD3<Float>, direction: SIMD3<Float>) -> GazeHit {
        guard let arView = arView else {
            return GazeHit(
                entity: nil,
                position: origin,
                normal: SIMD3<Float>(0, 1, 0),
                distance: 0,
                timestamp: Date(),
                confidence: 0
            )
        }

        // Perform RealityKit raycast
        let rayOrigin = origin
        let rayEnd = origin + direction * raycastMaxDistance

        // Cast ray and check for intersections
        if let result = arView.scene.raycast(
            origin: rayOrigin,
            direction: direction,
            length: raycastMaxDistance,
            query: .all,
            mask: .default,
            relativeTo: nil
        ).first {
            successfulHits += 1

            return GazeHit(
                entity: result.entity,
                position: result.position,
                normal: result.normal ?? SIMD3<Float>(0, 1, 0),
                distance: result.distance,
                timestamp: Date(),
                confidence: calculateConfidence(result)
            )
        }

        return GazeHit(
            entity: nil,
            position: rayEnd,
            normal: SIMD3<Float>(0, 1, 0),
            distance: raycastMaxDistance,
            timestamp: Date(),
            confidence: 0
        )
    }

    private func calculateConfidence(_ result: CollisionCastHit) -> Float {
        var confidence: Float = 1.0

        // Reduce confidence for distant targets
        let distanceFactor = 1.0 - (result.distance / raycastMaxDistance)
        confidence *= distanceFactor

        // Increase confidence if entity has collision
        if result.entity.collision != nil {
            confidence *= 1.2
        }

        return min(1.0, confidence)
    }

    // MARK: - Target Smoothing

    private func updateSmoothedTarget() {
        // Count votes for each entity in history
        var entityVotes: [ObjectIdentifier: Int] = [:]

        for hit in gazeHistory {
            if let entity = hit.entity {
                let id = ObjectIdentifier(entity)
                entityVotes[id, default: 0] += 1
            }
        }

        // Find most common target
        let mostCommon = entityVotes.max { $0.value < $1.value }

        if let (targetID, votes) = mostCommon {
            let voteFraction = Float(votes) / Float(gazeHistory.count)

            if voteFraction >= smoothingFactor {
                // Find entity with this ID
                if let hit = gazeHistory.last(where: { hit in
                    if let entity = hit.entity {
                        return ObjectIdentifier(entity) == targetID
                    }
                    return false
                }) {
                    smoothedTarget = hit.entity
                    currentTarget = hit.entity
                    gazeConfidence = voteFraction
                    return
                }
            }
        }

        // No consistent target
        smoothedTarget = nil
        currentTarget = nil
        gazeConfidence = 0
    }

    // MARK: - Selection

    /// Check if current gaze target meets selection threshold
    func canSelect() -> Bool {
        return gazeConfidence >= selectionThreshold && currentTarget != nil
    }

    /// Select current gaze target
    func selectTarget() -> Entity? {
        guard canSelect(), let target = currentTarget else {
            return nil
        }

        selections += 1

        NotificationCenter.default.post(
            name: .gazeTargetSelected,
            object: target
        )

        return target
    }

    /// Get current gaze hit position
    func getGazePosition() -> SIMD3<Float>? {
        return gazeHistory.last?.position
    }

    /// Get current gaze normal
    func getGazeNormal() -> SIMD3<Float>? {
        return gazeHistory.last?.normal
    }

    // MARK: - Configuration

    func setRaycastDistance(_ distance: Float) {
        raycastMaxDistance = max(1.0, distance)
        print("Gaze raycast distance: \(raycastMaxDistance)m")
    }

    func setSelectionThreshold(_ threshold: Float) {
        selectionThreshold = max(0.0, min(1.0, threshold))
        print("Selection threshold: \(String(format: "%.2f", selectionThreshold))")
    }

    func setSmoothingFactor(_ factor: Float) {
        smoothingFactor = max(0.0, min(1.0, factor))
        print("Smoothing factor: \(String(format: "%.2f", smoothingFactor))")
    }

    // MARK: - Statistics

    func getGazeStats() -> GazeTargetingStats {
        let hitRate = raycasts > 0 ? Float(successfulHits) / Float(raycasts) : 0

        return GazeTargetingStats(
            isEnabled: isEnabled,
            hasTarget: currentTarget != nil,
            gazeConfidence: gazeConfidence,
            raycasts: raycasts,
            successfulHits: successfulHits,
            hitRate: hitRate,
            selections: selections,
            historySize: gazeHistory.count
        )
    }

    func getDebugInfo() -> String {
        let stats = getGazeStats()

        var info = "=== Physics Gaze Targeting ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Has Target: \(stats.hasTarget)\n"

        if let target = currentTarget {
            info += "Target: \(target.name)\n"
        }

        info += "Confidence: \(String(format: "%.2f", stats.gazeConfidence * 100))%\n"
        info += "Can Select: \(canSelect())\n"
        info += "Raycasts: \(stats.raycasts)\n"
        info += "Hit Rate: \(String(format: "%.1f", stats.hitRate * 100))%\n"
        info += "Selections: \(stats.selections)\n"
        info += "History: \(stats.historySize)/\(historySize)\n"
        info += "============================="

        return info
    }
}

struct GazeTargetingStats {
    let isEnabled: Bool
    let hasTarget: Bool
    let gazeConfidence: Float
    let raycasts: Int
    let successfulHits: Int
    let hitRate: Float
    let selections: Int
    let historySize: Int
}

extension Notification.Name {
    static let gazeTargetSelected = Notification.Name("gazeTargetSelected")
}
