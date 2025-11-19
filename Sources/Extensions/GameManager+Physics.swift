import Foundation
import RealityKit
import Combine

extension GameManager {
    /// Associated physics manager
    var physicsManager: PhysicsManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.physicsManager) as? PhysicsManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.physicsManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Setup physics system and listeners
    func setupPhysics(manager: PhysicsManager) {
        self.physicsManager = manager
        // Listen for physics collisions
        NotificationCenter.default.publisher(for: .physicsCollision)
            .sink { [weak self] notification in
                guard let bodyA = notification.userInfo?["bodyA"] as? PhysicsBody,
                      let bodyB = notification.userInfo?["bodyB"] as? PhysicsBody else { return }
                self?.handlePhysicsCollision(bodyA, bodyB)
            }
            .store(in: &cancellables)

        // Start physics simulation
        manager.startSimulation()

        // Setup local player physics if exists
        if let localPlayer = localPlayer {
            localPlayer.setupPhysics(physicsManager: manager)
        }

        print("Physics system initialized")
    }

    /// Update physics system (call from game loop)
    func updatePhysics(deltaTime: Float) {
        guard let physicsManager = physicsManager else { return }

        // Update physics simulation
        physicsManager.update(deltaTime: deltaTime)

        // Update local player with physics
        if GameConfig.physicsEnabled, let localPlayer = localPlayer {
            // Apply movement using physics
            if length(movementDirection) > 0 {
                localPlayer.moveWithPhysics(direction: movementDirection, speed: GameConfig.defaultPlayerSpeed * 100)
            }

            localPlayer.updateWithPhysics(deltaTime: deltaTime)
        }

        // Update remote players
        for (_, player) in remotePlayers {
            if player.physicsBody != nil {
                player.updateWithPhysics(deltaTime: deltaTime)
            }
        }
    }

    /// Handle physics collision events
    private func handlePhysicsCollision(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody) {
        // Example: Check if player collided with item
        if isPlayerBody(bodyA) && isItemBody(bodyB) {
            collectItem(bodyB)
        } else if isPlayerBody(bodyB) && isItemBody(bodyA) {
            collectItem(bodyA)
        }

        // Add your game-specific collision logic here
        print("Collision detected between bodies")
    }

    private func isPlayerBody(_ body: PhysicsBody) -> Bool {
        return (body.collisionLayer & PhysicsLayer.player.rawValue) != 0
    }

    private func isItemBody(_ body: PhysicsBody) -> Bool {
        return (body.collisionLayer & PhysicsLayer.item.rawValue) != 0
    }

    private func collectItem(_ item: PhysicsBody) {
        // Remove item from physics and scene
        item.entity?.removeFromParent()
        print("Item collected!")
    }

    /// Create physics bodies for spatial planes
    func createPhysicsForPlanes(manager: SpatialTrackingManager, physicsManager: PhysicsManager) {
        for (_, plane) in manager.detectedPlanes {
            // Create static physics body for each plane
            let body = PhysicsBody.builder()
                .at(position: plane.center)
                .withCollider(.box(size: SIMD3<Float>(2, 0.1, 2)))  // Simplified
                .withMaterial(.default)
                .asStatic()
                .onLayer(PhysicsLayer.environment.rawValue)
                .build()

            physicsManager.addPhysicsBody(body)
        }
    }

    /// Movement direction property (for physics integration)
    var movementDirection: SIMD3<Float> {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.movementDirection) as? SIMD3<Float> ?? .zero
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.movementDirection, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - Physics Helpers for Spatial Integration

extension GameManager {
    /// Create a physics-enabled object
    func createPhysicsObject(
        at position: SIMD3<Float>,
        shape: ColliderShape = .sphere(radius: 0.1),
        material: PhysicsMaterial = .default,
        physicsManager: PhysicsManager
    ) -> ModelEntity? {
        guard let rootEntity = rootEntity else { return nil }

        // Create visual entity
        let mesh: MeshResource
        switch shape {
        case .sphere(let radius):
            mesh = MeshResource.generateSphere(radius: radius)
        case .box(let size):
            mesh = MeshResource.generateBox(size: size)
        case .capsule(let height, let radius):
            mesh = MeshResource.generateBox(size: SIMD3<Float>(radius * 2, height, radius * 2))
        }

        var visualMaterial = SimpleMaterial()
        visualMaterial.color = .init(tint: .orange)
        visualMaterial.metallic = 0.5
        visualMaterial.roughness = 0.5

        let entity = ModelEntity(mesh: mesh, materials: [visualMaterial])
        entity.position = position

        // Create physics body
        let physicsBody = PhysicsBody.builder()
            .at(position: position)
            .withCollider(shape)
            .withMaterial(material)
            .withMass(1.0)
            .build()

        physicsBody.entity = entity
        physicsManager.addPhysicsBody(physicsBody)

        rootEntity.addChild(entity)

        return entity
    }

    /// Apply explosion force to nearby physics bodies
    func applyExplosion(
        at position: SIMD3<Float>,
        force: Float,
        radius: Float,
        physicsManager: PhysicsManager
    ) {
        for (_, body) in physicsManager.physicsBodies {
            let delta = body.position - position
            let distance = length(delta)

            guard distance < radius else { continue }
            guard body.isDynamic else { continue }

            // Calculate force falloff
            let falloff = 1.0 - (distance / radius)
            let explosionForce = normalize(delta) * force * falloff

            body.addImpulse(explosionForce)
        }
    }

    /// Check if a position is valid (not inside a collider)
    func isValidPosition(_ position: SIMD3<Float>, physicsManager: PhysicsManager) -> Bool {
        for (_, body) in physicsManager.physicsBodies {
            guard body.detectCollisions else { continue }

            let distance = length(body.position - position)
            if distance < body.boundingRadius {
                return false
            }
        }
        return true
    }

    /// Spawn a physics-enabled power-up
    func spawnPhysicsPowerUp(at position: SIMD3<Float>, physicsManager: PhysicsManager) {
        let _ = createPhysicsObject(
            at: position,
            shape: .sphere(radius: 0.15),
            material: GameConfig.itemMaterial,
            physicsManager: physicsManager
        )
    }
}

private struct AssociatedKeys {
    static var physicsManager = "physicsManager"
    static var movementDirection = "movementDirection"
}
