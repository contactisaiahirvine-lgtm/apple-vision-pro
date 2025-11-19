import Foundation
import Combine
import ObjectiveC

extension GameManager {
    // MARK: - Associated Properties

    var ecsManager: ECSManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.ecsManager) as? ECSManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.ecsManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var gazeTrackingManager: GazeTrackingManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.gazeTrackingManager) as? GazeTrackingManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.gazeTrackingManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var gestureManager: GestureManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.gestureManager) as? GestureManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.gestureManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var spatialAudioManager: SpatialAudioManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.spatialAudioManager) as? SpatialAudioManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.spatialAudioManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Engine Setup

    /// Setup complete engine with all capabilities
    func setupEngine(arView: RealityKit.ARView) {
        setupECS()
        setupGazeTracking(arView: arView)
        setupGestureHandling(arView: arView)
        setupSpatialAudio(arView: arView)

        print("✅ Complete game engine initialized with ECS, gaze tracking, gestures, and spatial audio")
    }

    // MARK: - ECS Setup

    private func setupECS() {
        guard ecsManager == nil else { return }

        let ecs = ECSManager()
        ecsManager = ecs

        // Add core systems
        let movementSystem = MovementSystem()
        let lifetimeSystem = LifetimeSystem()
        let healthSystem = HealthSystem()
        let hierarchySystem = HierarchySystem()

        ecs.addSystem(movementSystem)
        ecs.addSystem(lifetimeSystem)
        ecs.addSystem(healthSystem)
        ecs.addSystem(hierarchySystem)

        // Add physics sync if physics is enabled
        if GameConfig.physicsEnabled, let physicsManager = physicsManager {
            let physicsSync = PhysicsSyncSystem(physicsManager: physicsManager)
            ecs.addSystem(physicsSync)
        }

        // Add render sync
        let renderSync = RenderSyncSystem()
        ecs.addSystem(renderSync)

        print("ECS initialized with \(ecs.systemCount) systems")
    }

    private func setupGazeTracking(arView: RealityKit.ARView) {
        guard gazeTrackingManager == nil else { return }

        let gaze = GazeTrackingManager()
        gazeTrackingManager = gaze
        gaze.setup(arView: arView)

        // Add gaze system to ECS
        if let ecs = ecsManager {
            let gazeSystem = GazeSystem(gazeManager: gaze)
            ecs.addSystem(gazeSystem)
        }

        // Enable dwell selection (gaze for 1.5 seconds to select)
        gaze.enableDwellSelection(duration: 1.5)

        print("Gaze tracking initialized")
    }

    private func setupGestureHandling(arView: RealityKit.ARView) {
        guard gestureManager == nil else { return }

        let gestures = GestureManager()
        gestureManager = gestures
        gestures.setup(arView: arView)

        // Setup gesture callbacks
        gestures.onEntityPinched = { [weak self] entity in
            print("Entity pinched: \(entity.name)")
            // Handle entity selection
        }

        gestures.onEntityDragged = { [weak self] entity, location in
            // Handle entity dragging
        }

        gestures.onRotate = { [weak self] angle in
            // Handle rotation gesture
        }

        gestures.onScale = { [weak self] scale in
            // Handle scale gesture
        }

        print("Gesture handling initialized")
    }

    private func setupSpatialAudio(arView: RealityKit.ARView) {
        guard spatialAudioManager == nil else { return }

        let audio = SpatialAudioManager()
        spatialAudioManager = audio
        audio.setup(arView: arView)

        // Add spatial audio system to ECS
        if let ecs = ecsManager {
            let audioSystem = SpatialAudioSystem(audioManager: audio)
            ecs.addSystem(audioSystem)
        }

        print("Spatial audio initialized")
    }

    // MARK: - ECS Integration

    /// Update ECS (call from game loop)
    func updateECS(deltaTime: TimeInterval) {
        ecsManager?.update(deltaTime: deltaTime)
    }

    /// Create game entity using ECS
    func createGameEntity(configure: (EntityBuilder) -> Void) -> Entity? {
        return ecsManager?.createEntity(configure: configure)
    }

    /// Example: Create a simple cube entity
    func createCubeEntity(at position: SIMD3<Float>) -> Entity? {
        return ecsManager?.createEntity { builder in
            builder
                .with(TransformComponent(position: position))
                .with(RenderableComponent(assetName: "cube"))
                .with(TagComponent(tag: "cube"))
        }
    }

    /// Example: Create a moving sphere entity
    func createMovingSphere(at position: SIMD3<Float>, velocity: SIMD3<Float>) -> Entity? {
        return ecsManager?.createEntity { builder in
            builder
                .with(TransformComponent(position: position))
                .with(RenderableComponent(assetName: "sphere"))
                .with(VelocityComponent(linear: velocity))
                .with(LifetimeComponent(duration: 5.0))  // Destroy after 5 seconds
                .with(TagComponent(tag: "projectile"))
        }
    }

    /// Example: Create entity with health and physics
    func createEnemyEntity(at position: SIMD3<Float>) -> Entity? {
        return ecsManager?.createEntity { builder in
            builder
                .with(TransformComponent(position: position))
                .with(RenderableComponent(assetName: "target"))
                .with(HealthComponent(maximum: 100.0, onDeath: { entity in
                    print("Enemy destroyed!")
                }))
                .with(PhysicsComponent(mass: 2.0))
                .with(TagComponent(tag: "enemy"))
        }
    }

    /// Example: Create sound-emitting entity
    func createAudioEntity(at position: SIMD3<Float>, audioFile: String) -> Entity? {
        return ecsManager?.createEntity { builder in
            builder
                .with(TransformComponent(position: position))
                .with(AudioSourceComponent(audioFileName: audioFile, isLooping: true))
                .with(TagComponent(tag: "audio_source"))
        }
    }

    // MARK: - ECS Queries

    /// Find entities by tag
    func findEntitiesByTag(_ tag: String) -> [Entity] {
        return ecsManager?.entitiesWithTag(tag) ?? []
    }

    /// Find entities near position
    func findEntitiesNear(position: SIMD3<Float>, radius: Float) -> [Entity] {
        return ecsManager?.entitiesNear(position: position, radius: radius) ?? []
    }

    /// Find closest entity to position
    func findClosestEntity(to position: SIMD3<Float>, withTag tag: String? = nil) -> Entity? {
        return ecsManager?.closestEntity(to: position, withTag: tag)
    }

    // MARK: - Component Access

    /// Get component from entity
    func getComponent<T: Component>(from entity: Entity) -> T? {
        return ecsManager?.getComponent(for: entity)
    }

    /// Update component on entity
    func updateComponent<T: Component>(_ component: T, on entity: Entity) {
        ecsManager?.updateComponent(component, for: entity)
    }

    /// Add component to entity
    func addComponent<T: Component>(_ component: T, to entity: Entity) {
        ecsManager?.addComponent(component, to: entity)
    }

    // MARK: - Gaze Interaction

    /// Check if gazing at entity
    func isGazingAt(_ entity: RealityKit.Entity) -> Bool {
        return gazeTrackingManager?.isGazingAt(entity) ?? false
    }

    /// Get current gaze target
    var currentGazeTarget: RealityKit.Entity? {
        return gazeTrackingManager?.currentGazeTarget
    }

    // MARK: - Spatial Audio Helpers

    /// Play 3D sound at position
    func playSound(_ filename: String, at position: SIMD3<Float>, volume: Float = 1.0) {
        spatialAudioManager?.playSFX(filename, at: position, volume: volume)
    }

    /// Play sound on entity
    func playSoundOn(entity: RealityKit.Entity, named filename: String) {
        _ = spatialAudioManager?.playSoundOn(entity: entity, named: filename)
    }

    /// Preload audio files
    func preloadAudio(_ filenames: [String]) async {
        await spatialAudioManager?.preloadAudioFiles(filenames)
    }

    // MARK: - Statistics

    /// Get ECS statistics
    func getECSStats() -> ECSStatistics? {
        return ecsManager?.getStatistics()
    }

    /// Print engine debug info
    func printEngineDebug() {
        print("=== Engine Debug Info ===")
        ecsManager?.printDebugInfo()

        if let gazeManager = gazeTrackingManager {
            print("Gaze Tracking: \(gazeManager.isGazeTrackingActive ? "Active" : "Inactive")")
            if let target = gazeManager.currentGazeTarget {
                print("  Current Target: \(target.name)")
            }
        }

        if let gestureManager = gestureManager {
            print("Gesture: \(gestureManager.currentGestureType)")
        }

        if let audioManager = spatialAudioManager {
            print("Active Sounds: \(audioManager.activeSounds.count)")
        }

        print("========================")
    }
}

// MARK: - Associated Keys Extension

private extension AssociatedKeys {
    static var ecsManager = "ecsManager"
    static var gazeTrackingManager = "gazeTrackingManager"
    static var gestureManager = "gestureManager"
    static var spatialAudioManager = "spatialAudioManager"
}
