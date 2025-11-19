import Foundation
import RealityKit
import simd

extension Player {
    /// Physics body associated with this player
    var physicsBody: PhysicsBody? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.physicsBody) as? PhysicsBody
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.physicsBody, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Setup physics for this player
    func setupPhysics(physicsManager: PhysicsManager) {
        // Create physics body for player
        let body = PhysicsBody.builder()
            .at(position: position)
            .withRotation(rotation)
            .withCollider(.capsule(height: 0.4, radius: 0.1))  // Capsule for character
            .withMaterial(.default)
            .withMass(70.0)  // ~70kg player mass
            .withGravity(true)
            .onLayer(PhysicsLayer.player.rawValue)
            .collidingWith(PhysicsLayer.environment.rawValue | PhysicsLayer.item.rawValue)
            .build()

        // Constrain rotation for character controller
        body.addConstraint(.freezeRotation)

        // Link entity
        body.entity = entity

        // Setup collision callbacks
        body.onCollisionEnter = { [weak self] otherBody in
            self?.handleCollisionEnter(otherBody)
        }

        // Add to physics manager
        physicsManager.addPhysicsBody(body)
        self.physicsBody = body

        print("Physics setup for player: \(name)")
    }

    /// Update player using physics
    func updateWithPhysics(deltaTime: Float) {
        guard let physicsBody = physicsBody else {
            // Fallback to old movement system
            updatePosition(deltaTime: deltaTime)
            return
        }

        // Sync position from physics
        position = physicsBody.position
        rotation = physicsBody.rotation

        // Update entity
        updateEntityTransform()
    }

    /// Move player using physics forces
    func moveWithPhysics(direction: SIMD3<Float>, speed: Float = 2.0) {
        guard let physicsBody = physicsBody else {
            // Fallback to old movement
            move(direction: direction, speed: speed)
            return
        }

        // SAFETY: Check for zero vector to prevent NaN
        let dirLength = simd_length(direction)
        guard dirLength > 0.001 else { return }

        let normalizedDirection = direction / dirLength
        let force = normalizedDirection * speed * physicsBody.mass

        physicsBody.addForce(force)
    }

    /// Jump using physics
    func jump(force: Float = 300.0) {
        guard let physicsBody = physicsBody else { return }

        // Only jump if grounded (simplified check)
        if abs(physicsBody.velocity.y) < 0.5 {
            physicsBody.addImpulse(SIMD3<Float>(0, force / physicsBody.mass, 0))
        }
    }

    /// Apply dash/boost
    func dash(direction: SIMD3<Float>, force: Float = 500.0) {
        guard let physicsBody = physicsBody else { return }

        let normalizedDirection = length(direction) > 0.001 ? normalize(direction) : .zero
        let impulse = normalizedDirection * (force / physicsBody.mass)

        physicsBody.addImpulse(impulse)
    }

    /// Handle collision with another physics body
    private func handleCollisionEnter(_ otherBody: PhysicsBody) {
        // Check what type of object was hit
        if (otherBody.collisionLayer & PhysicsLayer.item.rawValue) != 0 {
            // Collected an item
            NotificationCenter.default.post(
                name: .playerCollectedItem,
                object: nil,
                userInfo: ["player": self, "item": otherBody]
            )
        }

        if (otherBody.collisionLayer & PhysicsLayer.environment.rawValue) != 0 {
            // Hit environment (wall, floor, etc.)
            // Could play sound, particle effect, etc.
        }
    }

    /// Check if player is grounded (on floor)
    func isGrounded(physicsManager: PhysicsManager) -> Bool {
        guard let physicsBody = physicsBody else { return false }

        // Raycast downward
        let origin = physicsBody.position
        let direction = SIMD3<Float>(0, -1, 0)

        if let hit = physicsManager.raycast(origin: origin, direction: direction, maxDistance: 0.3) {
            // Check if hit is environment (floor)
            return (hit.body.collisionLayer & PhysicsLayer.environment.rawValue) != 0
        }

        return false
    }

    /// Get velocity magnitude
    var speed: Float {
        guard let physicsBody = physicsBody else {
            return length(velocity)
        }
        return length(physicsBody.velocity)
    }

    /// Stop all movement
    func stopMovement() {
        if let physicsBody = physicsBody {
            physicsBody.velocity = SIMD3<Float>(physicsBody.velocity.x * 0.1, physicsBody.velocity.y, physicsBody.velocity.z * 0.1)
        } else {
            velocity = .zero
        }
    }

    /// Teleport player (resets physics)
    func teleportWithPhysics(to position: SIMD3<Float>) {
        if let physicsBody = physicsBody {
            physicsBody.teleport(to: position)
        }
        self.position = position
        updateEntityTransform()
    }
}

private struct AssociatedKeys {
    static var physicsBody = "physicsBody"
}

// MARK: - Notifications

extension Notification.Name {
    static let playerCollectedItem = Notification.Name("playerCollectedItem")
}
