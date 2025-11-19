import Foundation
import RealityKit
import ARKit
import Combine

/// Manages ARKit world anchors for stable 3D object placement
@MainActor
class AnchorManager: ObservableObject {

    // MARK: - Published Properties

    @Published var worldAnchors: [UUID: AnchorEntity] = [:]
    @Published var isTrackingStable = false
    @Published var anchorCount = 0

    // MARK: - Private Properties

    private weak var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        print("AnchorManager initialized")
    }

    func setup(arView: ARView) {
        self.arView = arView
        setupARConfiguration()
    }

    // MARK: - AR Configuration

    private func setupARConfiguration() {
        guard let arView = arView else { return }

        #if targetEnvironment(simulator)
        print("Running in simulator - AR features limited")
        #else
        // Configure world tracking
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification

        // Enable world map persistence
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(configuration)
        print("AR world tracking configured")
        #endif
    }

    // MARK: - Anchor Creation

    /// Create a world anchor at a specific position
    func createWorldAnchor(at position: SIMD3<Float>) async throws -> AnchorEntity {
        guard let arView = arView else {
            throw AnchorError.arViewNotInitialized
        }

        // Create anchor entity
        let anchor = AnchorEntity(world: position)
        anchor.name = "WorldAnchor_\(UUID().uuidString)"

        // Track anchor
        let id = UUID()
        worldAnchors[id] = anchor

        anchorCount = worldAnchors.count

        print("Created world anchor at \(position)")

        return anchor
    }

    /// Create an anchor attached to a detected plane
    func createPlaneAnchor(on planeAnchor: ARPlaneAnchor) -> AnchorEntity {
        let anchor = AnchorEntity(anchor: planeAnchor)
        anchor.name = "PlaneAnchor_\(planeAnchor.identifier)"

        let id = UUID()
        worldAnchors[id] = anchor

        anchorCount = worldAnchors.count

        print("Created plane anchor for plane: \(planeAnchor.identifier)")

        return anchor
    }

    /// Create an anchor at device camera position
    func createCameraAnchor() async throws -> AnchorEntity {
        guard let arView = arView else {
            throw AnchorError.arViewNotInitialized
        }

        let cameraTransform = arView.cameraTransform
        let position = SIMD3<Float>(
            cameraTransform.translation.x,
            cameraTransform.translation.y,
            cameraTransform.translation.z
        )

        return try await createWorldAnchor(at: position)
    }

    /// Create an anchor by raycasting from screen position
    func createRaycastAnchor(from screenPoint: CGPoint) async throws -> AnchorEntity {
        guard let arView = arView else {
            throw AnchorError.arViewNotInitialized
        }

        // Perform raycast
        let results = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        )

        guard let first = results.first else {
            throw AnchorError.raycastFailed
        }

        let position = SIMD3<Float>(
            first.worldTransform.columns.3.x,
            first.worldTransform.columns.3.y,
            first.worldTransform.columns.3.z
        )

        return try await createWorldAnchor(at: position)
    }

    // MARK: - Anchor Management

    /// Remove a specific anchor
    func removeAnchor(_ anchor: AnchorEntity) {
        anchor.removeFromParent()

        // Find and remove from tracking
        if let id = worldAnchors.first(where: { $0.value === anchor })?.key {
            worldAnchors.removeValue(forKey: id)
            anchorCount = worldAnchors.count
            print("Removed anchor: \(id)")
        }
    }

    /// Remove all anchors
    func removeAllAnchors() {
        for (_, anchor) in worldAnchors {
            anchor.removeFromParent()
        }

        worldAnchors.removeAll()
        anchorCount = 0

        print("Removed all anchors")
    }

    /// Get anchor by ID
    func getAnchor(id: UUID) -> AnchorEntity? {
        return worldAnchors[id]
    }

    // MARK: - Anchor Persistence

    /// Save world map for anchor persistence
    func saveWorldMap() async throws -> ARWorldMap {
        guard let arView = arView else {
            throw AnchorError.arViewNotInitialized
        }

        return try await withCheckedThrowingContinuation { continuation in
            arView.session.getCurrentWorldMap { worldMap, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let worldMap = worldMap {
                    continuation.resume(returning: worldMap)
                } else {
                    continuation.resume(throwing: AnchorError.worldMapUnavailable)
                }
            }
        }
    }

    /// Load world map to restore anchors
    func loadWorldMap(_ worldMap: ARWorldMap) {
        guard let arView = arView else { return }

        let configuration = ARWorldTrackingConfiguration()
        configuration.initialWorldMap = worldMap
        configuration.planeDetection = [.horizontal, .vertical]

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        print("Loaded world map with \(worldMap.anchors.count) anchors")
    }

    // MARK: - Anchor Utilities

    /// Snap position to nearest detected plane
    func snapToPlane(position: SIMD3<Float>) -> SIMD3<Float>? {
        guard let arView = arView else { return nil }

        // Find nearest plane
        var nearestPlane: ARPlaneAnchor?
        var nearestDistance: Float = .infinity

        for anchor in arView.session.currentFrame?.anchors ?? [] {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }

            let planePosition = SIMD3<Float>(
                planeAnchor.transform.columns.3.x,
                planeAnchor.transform.columns.3.y,
                planeAnchor.transform.columns.3.z
            )

            let distance = simd_distance(position, planePosition)

            if distance < nearestDistance {
                nearestDistance = distance
                nearestPlane = planeAnchor
            }
        }

        guard let plane = nearestPlane, nearestDistance < 0.5 else {
            return nil
        }

        // Snap to plane height
        let planeY = plane.transform.columns.3.y
        return SIMD3<Float>(position.x, planeY, position.z)
    }

    /// Check if anchor tracking is stable
    func updateTrackingState() {
        guard let arView = arView,
              let frame = arView.session.currentFrame else {
            isTrackingStable = false
            return
        }

        switch frame.camera.trackingState {
        case .normal:
            isTrackingStable = true
        case .limited, .notAvailable:
            isTrackingStable = false
        }
    }

    // MARK: - Visualization

    /// Add debug visualization for anchors
    func visualizeAnchors(enabled: Bool) {
        guard let arView = arView else { return }

        if enabled {
            arView.debugOptions.insert(.showAnchorOrigins)
            arView.debugOptions.insert(.showAnchorGeometry)
        } else {
            arView.debugOptions.remove(.showAnchorOrigins)
            arView.debugOptions.remove(.showAnchorGeometry)
        }

        print("Anchor visualization: \(enabled)")
    }

    // MARK: - Anchor Validation

    /// Validate that anchor is still being tracked
    func isAnchorValid(_ anchor: AnchorEntity) -> Bool {
        guard let arView = arView else { return false }

        // Check if anchor exists in session
        for sessionAnchor in arView.session.currentFrame?.anchors ?? [] {
            if let planeAnchor = anchor.anchorIdentifier,
               sessionAnchor.identifier == planeAnchor {
                return true
            }
        }

        // World anchors are always valid unless removed
        return worldAnchors.values.contains(where: { $0 === anchor })
    }

    /// Get distance from camera to anchor
    func distanceFromCamera(to anchor: AnchorEntity) -> Float? {
        guard let arView = arView else { return nil }

        let cameraTransform = arView.cameraTransform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.translation.x,
            cameraTransform.translation.y,
            cameraTransform.translation.z
        )

        let anchorPosition = anchor.position(relativeTo: nil)

        return simd_distance(cameraPosition, anchorPosition)
    }
}

// MARK: - Anchor Error

enum AnchorError: LocalizedError {
    case arViewNotInitialized
    case raycastFailed
    case worldMapUnavailable
    case invalidAnchor
    case trackingLost

    var errorDescription: String? {
        switch self {
        case .arViewNotInitialized:
            return "ARView not initialized"
        case .raycastFailed:
            return "Raycast did not hit any surface"
        case .worldMapUnavailable:
            return "World map is not available"
        case .invalidAnchor:
            return "Anchor is invalid or no longer tracked"
        case .trackingLost:
            return "AR tracking has been lost"
        }
    }
}

// MARK: - Transform Extensions

extension Transform {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }
}
