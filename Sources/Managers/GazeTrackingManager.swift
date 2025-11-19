import Foundation
import ARKit
import RealityKit
import Combine

/// Manages eye gaze tracking for Vision Pro
@MainActor
class GazeTrackingManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isGazeTrackingActive = false
    @Published var currentGazeTarget: Entity?
    @Published var gazePosition: SIMD3<Float>?
    @Published var gazeDirection: SIMD3<Float>?

    // MARK: - Private Properties

    private weak var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    private var lastGazeTarget: Entity?
    private let gazeRayLength: Float = 10.0

    // MARK: - Callbacks

    var onGazeEnter: ((Entity) -> Void)?
    var onGazeExit: ((Entity) -> Void)?
    var onGazeStay: ((Entity, TimeInterval) -> Void)?

    private var gazeStartTime: Date?
    private var gazeDuration: TimeInterval = 0

    // MARK: - Initialization

    init() {
        print("GazeTrackingManager initialized")
    }

    func setup(arView: ARView) {
        self.arView = arView
        startGazeTracking()
    }

    // MARK: - Gaze Tracking

    func startGazeTracking() {
        #if targetEnvironment(simulator)
        print("Gaze tracking not available in simulator")
        #else
        guard let arView = arView else { return }

        // Check if eye tracking is supported
        guard ARFaceTrackingConfiguration.isSupported else {
            print("Eye tracking not supported on this device")
            return
        }

        isGazeTrackingActive = true
        print("Gaze tracking started")
        #endif
    }

    func stopGazeTracking() {
        isGazeTrackingActive = false
        currentGazeTarget = nil
        gazePosition = nil
        gazeDirection = nil
        print("Gaze tracking stopped")
    }

    // MARK: - Gaze Update

    /// Update gaze tracking (call from game loop)
    func update(deltaTime: TimeInterval) {
        guard isGazeTrackingActive,
              let arView = arView else {
            return
        }

        // Get current camera transform
        let cameraTransform = arView.cameraTransform

        // Extract camera position and forward direction
        let cameraPosition = SIMD3<Float>(
            cameraTransform.translation.x,
            cameraTransform.translation.y,
            cameraTransform.translation.z
        )

        // Camera forward is negative Z in camera space
        let cameraForward = SIMD3<Float>(
            -cameraTransform.matrix.columns.2.x,
            -cameraTransform.matrix.columns.2.y,
            -cameraTransform.matrix.columns.2.z
        )

        // In Vision Pro, gaze direction closely matches head direction
        // In a real implementation, you would use ARKit's eye tracking data
        gazePosition = cameraPosition
        gazeDirection = cameraForward

        // Perform raycast from gaze
        performGazeRaycast(origin: cameraPosition, direction: cameraForward)
    }

    private func performGazeRaycast(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        guard let arView = arView else { return }

        // Create ray
        let rayEnd = origin + direction * gazeRayLength

        // Perform collision test
        let results = arView.scene.raycast(
            origin: origin,
            direction: direction,
            length: gazeRayLength,
            query: .nearest,
            mask: .all,
            relativeTo: nil
        )

        if let hit = results.first {
            handleGazeHit(entity: hit.entity)
        } else {
            handleGazeMiss()
        }
    }

    private func handleGazeHit(entity: Entity) {
        // Check if this is a new target
        if currentGazeTarget != entity {
            // Exit previous target
            if let previous = currentGazeTarget {
                onGazeExit?(previous)
                gazeDuration = 0
                gazeStartTime = nil
            }

            // Enter new target
            currentGazeTarget = entity
            lastGazeTarget = entity
            gazeStartTime = Date()
            onGazeEnter?(entity)

            // Post notification
            NotificationCenter.default.post(
                name: .gazeTargetChanged,
                object: nil,
                userInfo: ["entity": entity]
            )
        } else {
            // Stay on same target
            if let startTime = gazeStartTime {
                gazeDuration = Date().timeIntervalSince(startTime)
                onGazeStay?(entity, gazeDuration)
            }
        }
    }

    private func handleGazeMiss() {
        if let previous = currentGazeTarget {
            onGazeExit?(previous)
            currentGazeTarget = nil
            gazeDuration = 0
            gazeStartTime = nil

            NotificationCenter.default.post(
                name: .gazeTargetCleared,
                object: nil,
                userInfo: [:]
            )
        }
    }

    // MARK: - Gaze Selection

    /// Dwell-time selection (gaze at object for duration)
    func enableDwellSelection(duration: TimeInterval = 1.5) {
        onGazeStay = { [weak self] entity, gazeDuration in
            if gazeDuration >= duration {
                self?.selectTarget(entity)
            }
        }
    }

    private func selectTarget(_ entity: Entity) {
        NotificationCenter.default.post(
            name: .gazeTargetSelected,
            object: nil,
            userInfo: ["entity": entity]
        )

        print("Gaze selected: \(entity.name)")

        // Reset to prevent repeated selections
        currentGazeTarget = nil
        gazeDuration = 0
        gazeStartTime = nil
    }

    // MARK: - Visual Feedback

    /// Add visual cursor at gaze point
    func createGazeCursor() -> Entity? {
        guard let arView = arView else { return nil }

        // Create small sphere as cursor
        let mesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: .white.withAlphaComponent(0.8), isMetallic: false)
        let cursorEntity = ModelEntity(mesh: mesh, materials: [material])

        cursorEntity.name = "GazeCursor"

        arView.scene.addAnchor(AnchorEntity(world: .zero))

        return cursorEntity
    }

    /// Update cursor position to follow gaze
    func updateGazeCursor(_ cursor: Entity) {
        guard let position = gazePosition,
              let direction = gazeDirection else {
            cursor.isEnabled = false
            return
        }

        cursor.isEnabled = true

        // Place cursor 1 meter in front of gaze origin
        let cursorDistance: Float = 1.0
        let cursorPosition = position + direction * cursorDistance

        cursor.position = cursorPosition
    }

    // MARK: - Utilities

    /// Get gaze hit point on plane
    func getGazeHitOnPlane(planeNormal: SIMD3<Float>, planePoint: SIMD3<Float>) -> SIMD3<Float>? {
        guard let origin = gazePosition,
              let direction = gazeDirection else {
            return nil
        }

        // Ray-plane intersection
        let denom = simd_dot(planeNormal, direction)

        // Check if ray is parallel to plane
        guard abs(denom) > 0.0001 else {
            return nil
        }

        let t = simd_dot(planePoint - origin, planeNormal) / denom

        // Check if intersection is in front of origin
        guard t >= 0 else {
            return nil
        }

        return origin + direction * t
    }

    /// Check if entity is being gazed at
    func isGazingAt(_ entity: Entity) -> Bool {
        return currentGazeTarget == entity
    }

    /// Get gaze duration on current target
    func getCurrentGazeDuration() -> TimeInterval {
        return gazeDuration
    }
}

// MARK: - Gaze Component (for ECS integration)

struct GazeTargetComponent: Component {
    var isGazedAt: Bool = false
    var gazeDuration: TimeInterval = 0
    var onGazeEnter: ((Entity) -> Void)?
    var onGazeExit: ((Entity) -> Void)?
    var onGazeSelect: ((Entity) -> Void)?
}

// MARK: - Gaze System (for ECS)

@MainActor
class GazeSystem: System {
    let name = "GazeSystem"
    let priority = 20  // Run early

    weak var gazeManager: GazeTrackingManager?

    init(gazeManager: GazeTrackingManager) {
        self.gazeManager = gazeManager
    }

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        guard let gazeManager = gazeManager else { return }

        // Update gaze tracking
        gazeManager.update(deltaTime: deltaTime)

        // Update gaze target components
        let entities = ecsManager.entitiesWith(GazeTargetComponent.self)

        for entity in entities {
            guard var gazeTarget: GazeTargetComponent = ecsManager.getComponent(for: entity),
                  let renderable: RenderableComponent = ecsManager.getComponent(for: entity),
                  let realityEntity = renderable.entity else {
                continue
            }

            let wasGazedAt = gazeTarget.isGazedAt
            let isGazedAt = gazeManager.isGazingAt(realityEntity)

            gazeTarget.isGazedAt = isGazedAt

            if isGazedAt {
                gazeTarget.gazeDuration += deltaTime

                if !wasGazedAt {
                    // Just started gazing
                    gazeTarget.onGazeEnter?(entity)
                }

                // Check for dwell selection (e.g., 2 seconds)
                if gazeTarget.gazeDuration >= 2.0 {
                    gazeTarget.onGazeSelect?(entity)
                    gazeTarget.gazeDuration = 0  // Reset after selection
                }
            } else {
                if wasGazedAt {
                    // Just stopped gazing
                    gazeTarget.onGazeExit?(entity)
                }
                gazeTarget.gazeDuration = 0
            }

            ecsManager.updateComponent(gazeTarget, for: entity)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let gazeTargetChanged = Notification.Name("gazeTargetChanged")
    static let gazeTargetCleared = Notification.Name("gazeTargetCleared")
    static let gazeTargetSelected = Notification.Name("gazeTargetSelected")
}
