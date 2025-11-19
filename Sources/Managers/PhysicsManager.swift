import Foundation
import RealityKit
import Combine

/// Manages physics simulation for all game objects
@MainActor
class PhysicsManager: ObservableObject {
    @Published var isSimulating = false
    @Published var gravity = GameConfig.gravity
    @Published var physicsBodies: [UUID: PhysicsBody] = [:]

    private var collisionPairs: Set<CollisionPair> = []
    private var physicsTask: Task<Void, Never>?

    // Physics configuration
    private let fixedTimeStep: Float = 1.0 / 60.0  // 60 Hz physics
    private var accumulator: Float = 0.0

    // Collision callbacks
    var onCollisionEnter: ((PhysicsBody, PhysicsBody) -> Void)?
    var onCollisionExit: ((PhysicsBody, PhysicsBody) -> Void)?
    var onCollisionStay: ((PhysicsBody, PhysicsBody) -> Void)?

    init() {
        setupDefaultCollisionHandlers()
    }

    // MARK: - Lifecycle

    func startSimulation() {
        guard !isSimulating else { return }
        isSimulating = true
        print("Physics simulation started")
    }

    func stopSimulation() {
        isSimulating = false
        physicsTask?.cancel()
        print("Physics simulation stopped")
    }

    // MARK: - Physics Body Management

    func addPhysicsBody(_ body: PhysicsBody) {
        physicsBodies[body.id] = body

        // Notify
        NotificationCenter.default.post(
            name: .physicsBodyAdded,
            object: nil,
            userInfo: ["body": body]
        )
    }

    func removePhysicsBody(_ id: UUID) {
        physicsBodies.removeValue(forKey: id)

        // Remove any collision pairs involving this body
        collisionPairs.removeAll { pair in
            pair.bodyA == id || pair.bodyB == id
        }
    }

    func getPhysicsBody(for id: UUID) -> PhysicsBody? {
        return physicsBodies[id]
    }

    // MARK: - Physics Update

    func update(deltaTime: Float) {
        guard isSimulating else { return }

        // Fixed timestep accumulator
        accumulator += deltaTime

        while accumulator >= fixedTimeStep {
            step(fixedTimeStep)
            accumulator -= fixedTimeStep
        }
    }

    private func step(_ dt: Float) {
        // 1. Apply forces and gravity
        applyForces(dt)

        // 2. Update velocities
        updateVelocities(dt)

        // 3. Detect collisions
        let detectedCollisions = detectCollisions()

        // 4. Resolve collisions
        resolveCollisions(detectedCollisions)

        // 5. Update positions
        updatePositions(dt)

        // 6. Handle collision callbacks
        handleCollisionCallbacks(detectedCollisions)

        // 7. Clear forces
        clearForces()
    }

    // MARK: - Force Application

    private func applyForces(_ dt: Float) {
        for (_, body) in physicsBodies {
            guard body.isDynamic else { continue }

            // Apply gravity
            if body.useGravity {
                body.addForce(gravity * body.mass)
            }

            // Apply drag
            let dragForce = -body.velocity * body.drag
            body.addForce(dragForce)

            // Apply angular drag
            body.angularVelocity *= (1.0 - body.angularDrag * dt)
        }
    }

    private func updateVelocities(_ dt: Float) {
        for (_, body) in physicsBodies {
            guard body.isDynamic else { continue }

            // SAFETY: Check for valid mass to prevent division by zero
            guard body.mass > 0.001 else {
                print("WARNING: Physics body has invalid mass: \(body.mass)")
                continue
            }

            // Linear velocity: v = v + (F/m) * dt
            let acceleration = body.force / body.mass
            body.velocity += acceleration * dt

            // Apply max velocity constraint
            let speed = length(body.velocity)
            if speed > body.maxVelocity && speed > 0.001 {
                // SAFETY: Safe division to prevent NaN
                body.velocity = (body.velocity / speed) * body.maxVelocity
            }

            // SAFETY: Check for valid moment of inertia
            guard body.momentOfInertia > 0.001 else {
                continue
            }

            // Angular velocity from torque
            // τ = I * α, where I is moment of inertia
            let angularAcceleration = body.torque / body.momentOfInertia
            body.angularVelocity += angularAcceleration * dt
        }
    }

    private func updatePositions(_ dt: Float) {
        for (_, body) in physicsBodies {
            guard body.isDynamic else { continue }

            // Update position
            body.position += body.velocity * dt

            // Update rotation
            let angVelLength = length(body.angularVelocity)
            if angVelLength > 0.001 {
                let angle = angVelLength * dt
                // SAFETY: Safe division to prevent NaN
                let axis = body.angularVelocity / angVelLength
                let deltaRotation = simd_quatf(angle: angle, axis: axis)
                body.rotation = deltaRotation * body.rotation
            }

            // Update entity transform
            body.updateEntityTransform()

            // Apply constraints
            applyConstraints(body)
        }
    }

    private func clearForces() {
        for (_, body) in physicsBodies {
            body.force = .zero
            body.torque = .zero
        }
    }

    // MARK: - Collision Detection

    private func detectCollisions() -> [Collision] {
        var collisions: [Collision] = []
        let bodies = Array(physicsBodies.values)

        // Broad phase: check all pairs
        for i in 0..<bodies.count {
            for j in (i+1)..<bodies.count {
                let bodyA = bodies[i]
                let bodyB = bodies[j]

                // Skip if both are static or kinematic
                if !bodyA.isDynamic && !bodyB.isDynamic {
                    continue
                }

                // Skip if collision disabled
                if !bodyA.detectCollisions || !bodyB.detectCollisions {
                    continue
                }

                // Check collision layers
                if !canCollide(bodyA, bodyB) {
                    continue
                }

                // Narrow phase: detailed collision check
                if let collision = checkCollision(bodyA, bodyB) {
                    collisions.append(collision)
                }
            }
        }

        return collisions
    }

    private func checkCollision(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody) -> Collision? {
        // Check based on collider shapes
        switch (bodyA.colliderShape, bodyB.colliderShape) {
        case (.sphere(let radiusA), .sphere(let radiusB)):
            return checkSphereSphere(bodyA, radiusA, bodyB, radiusB)

        case (.box(let sizeA), .box(let sizeB)):
            return checkBoxBox(bodyA, sizeA, bodyB, sizeB)

        case (.sphere(let radius), .box(let size)),
             (.box(let size), .sphere(let radius)):
            let (sphere, box) = bodyA.colliderShape == .sphere(radius) ? (bodyA, bodyB) : (bodyB, bodyA)
            return checkSphereBox(sphere, radius, box, size)

        case (.capsule(let height, let radius), .sphere(let radiusB)):
            return checkCapsuleSphere(bodyA, height, radius, bodyB, radiusB)

        default:
            // Fallback to bounding sphere check
            return checkBoundingSpheres(bodyA, bodyB)
        }
    }

    private func checkSphereSphere(_ bodyA: PhysicsBody, _ radiusA: Float,
                                   _ bodyB: PhysicsBody, _ radiusB: Float) -> Collision? {
        let delta = bodyB.position - bodyA.position
        let distance = length(delta)
        let minDistance = radiusA + radiusB

        if distance < minDistance {
            let normal = distance > 0.001 ? normalize(delta) : SIMD3<Float>(0, 1, 0)
            let penetration = minDistance - distance
            let contactPoint = bodyA.position + normal * radiusA

            return Collision(
                bodyA: bodyA.id,
                bodyB: bodyB.id,
                contactPoint: contactPoint,
                normal: normal,
                penetrationDepth: penetration
            )
        }

        return nil
    }

    private func checkBoxBox(_ bodyA: PhysicsBody, _ sizeA: SIMD3<Float>,
                            _ bodyB: PhysicsBody, _ sizeB: SIMD3<Float>) -> Collision? {
        // Axis-aligned bounding box collision (simplified)
        let minA = bodyA.position - sizeA * 0.5
        let maxA = bodyA.position + sizeA * 0.5
        let minB = bodyB.position - sizeB * 0.5
        let maxB = bodyB.position + sizeB * 0.5

        // Check overlap on all axes
        if maxA.x < minB.x || minA.x > maxB.x { return nil }
        if maxA.y < minB.y || minA.y > maxB.y { return nil }
        if maxA.z < minB.z || minA.z > maxB.z { return nil }

        // Calculate penetration and normal
        let delta = bodyB.position - bodyA.position
        let overlapX = min(maxA.x - minB.x, maxB.x - minA.x)
        let overlapY = min(maxA.y - minB.y, maxB.y - minA.y)
        let overlapZ = min(maxA.z - minB.z, maxB.z - minA.z)

        var normal = SIMD3<Float>(0, 1, 0)
        var penetration = overlapY

        if overlapX < penetration {
            penetration = overlapX
            normal = SIMD3<Float>(delta.x > 0 ? 1 : -1, 0, 0)
        }
        if overlapZ < penetration {
            penetration = overlapZ
            normal = SIMD3<Float>(0, 0, delta.z > 0 ? 1 : -1)
        }

        return Collision(
            bodyA: bodyA.id,
            bodyB: bodyB.id,
            contactPoint: bodyA.position + normal * penetration * 0.5,
            normal: normal,
            penetrationDepth: penetration
        )
    }

    private func checkSphereBox(_ sphere: PhysicsBody, _ radius: Float,
                               _ box: PhysicsBody, _ size: SIMD3<Float>) -> Collision? {
        let boxMin = box.position - size * 0.5
        let boxMax = box.position + size * 0.5

        // Find closest point on box to sphere center
        let closestPoint = SIMD3<Float>(
            max(boxMin.x, min(sphere.position.x, boxMax.x)),
            max(boxMin.y, min(sphere.position.y, boxMax.y)),
            max(boxMin.z, min(sphere.position.z, boxMax.z))
        )

        let delta = sphere.position - closestPoint
        let distance = length(delta)

        if distance < radius {
            let normal = distance > 0.001 ? normalize(delta) : SIMD3<Float>(0, 1, 0)
            let penetration = radius - distance

            return Collision(
                bodyA: sphere.id,
                bodyB: box.id,
                contactPoint: closestPoint,
                normal: normal,
                penetrationDepth: penetration
            )
        }

        return nil
    }

    private func checkCapsuleSphere(_ capsule: PhysicsBody, _ height: Float, _ capsuleRadius: Float,
                                   _ sphere: PhysicsBody, _ sphereRadius: Float) -> Collision? {
        // Simplified: treat capsule as sphere for now
        return checkSphereSphere(capsule, capsuleRadius, sphere, sphereRadius)
    }

    private func checkBoundingSpheres(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody) -> Collision? {
        let radiusA = bodyA.boundingRadius
        let radiusB = bodyB.boundingRadius
        return checkSphereSphere(bodyA, radiusA, bodyB, radiusB)
    }

    // MARK: - Collision Resolution

    private func resolveCollisions(_ collisions: [Collision]) {
        for collision in collisions {
            guard let bodyA = physicsBodies[collision.bodyA],
                  let bodyB = physicsBodies[collision.bodyB] else {
                continue
            }

            // Separate bodies
            separateBodies(bodyA, bodyB, collision)

            // Resolve collision based on physics materials
            resolveCollisionImpulse(bodyA, bodyB, collision)
        }
    }

    private func separateBodies(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody, _ collision: Collision) {
        let separation = collision.normal * collision.penetrationDepth

        if bodyA.isDynamic && bodyB.isDynamic {
            // Both dynamic: split separation
            bodyA.position -= separation * 0.5
            bodyB.position += separation * 0.5
        } else if bodyA.isDynamic {
            // Only A is dynamic
            bodyA.position -= separation
        } else if bodyB.isDynamic {
            // Only B is dynamic
            bodyB.position += separation
        }

        bodyA.updateEntityTransform()
        bodyB.updateEntityTransform()
    }

    private func resolveCollisionImpulse(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody, _ collision: Collision) {
        // Calculate relative velocity at contact point
        let relativeVelocity = bodyB.velocity - bodyA.velocity
        let velocityAlongNormal = simd_dot(relativeVelocity, collision.normal)

        // Don't resolve if velocities are separating
        if velocityAlongNormal > 0 { return }

        // Calculate restitution (bounciness)
        let restitution = min(bodyA.material.bounciness, bodyB.material.bounciness)

        // Calculate impulse magnitude
        var impulseMagnitude = -(1.0 + restitution) * velocityAlongNormal

        if bodyA.isDynamic && bodyB.isDynamic {
            impulseMagnitude /= (1.0 / bodyA.mass) + (1.0 / bodyB.mass)
        } else if bodyA.isDynamic {
            impulseMagnitude /= (1.0 / bodyA.mass)
        } else if bodyB.isDynamic {
            impulseMagnitude /= (1.0 / bodyB.mass)
        }

        // Apply impulse
        let impulse = collision.normal * impulseMagnitude

        if bodyA.isDynamic {
            bodyA.velocity -= impulse / bodyA.mass
        }
        if bodyB.isDynamic {
            bodyB.velocity += impulse / bodyB.mass
        }

        // Apply friction
        applyFriction(bodyA, bodyB, collision, impulseMagnitude)
    }

    private func applyFriction(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody,
                              _ collision: Collision, _ normalImpulse: Float) {
        let relativeVelocity = bodyB.velocity - bodyA.velocity

        // Calculate tangent (perpendicular to normal)
        let velocityAlongNormal = simd_dot(relativeVelocity, collision.normal)
        let tangentVelocity = relativeVelocity - collision.normal * velocityAlongNormal

        guard length(tangentVelocity) > 0.001 else { return }

        let tangent = normalize(tangentVelocity)

        // Calculate friction coefficient
        let friction = sqrt(bodyA.material.friction * bodyB.material.friction)

        // Calculate friction impulse
        var frictionMagnitude = -simd_dot(relativeVelocity, tangent)

        if bodyA.isDynamic && bodyB.isDynamic {
            frictionMagnitude /= (1.0 / bodyA.mass) + (1.0 / bodyB.mass)
        } else if bodyA.isDynamic {
            frictionMagnitude /= (1.0 / bodyA.mass)
        } else if bodyB.isDynamic {
            frictionMagnitude /= (1.0 / bodyB.mass)
        }

        // Coulomb friction
        let maxFriction = abs(normalImpulse * friction)
        frictionMagnitude = max(-maxFriction, min(frictionMagnitude, maxFriction))

        let frictionImpulse = tangent * frictionMagnitude

        if bodyA.isDynamic {
            bodyA.velocity -= frictionImpulse / bodyA.mass
        }
        if bodyB.isDynamic {
            bodyB.velocity += frictionImpulse / bodyB.mass
        }
    }

    // MARK: - Constraints

    private func applyConstraints(_ body: PhysicsBody) {
        // Apply position constraints
        for constraint in body.constraints {
            switch constraint {
            case .freezePositionX:
                body.position.x = body.constrainedPosition.x
                body.velocity.x = 0
            case .freezePositionY:
                body.position.y = body.constrainedPosition.y
                body.velocity.y = 0
            case .freezePositionZ:
                body.position.z = body.constrainedPosition.z
                body.velocity.z = 0
            case .freezeRotation:
                body.angularVelocity = .zero
            }
        }
    }

    // MARK: - Collision Callbacks

    private func handleCollisionCallbacks(_ detectedCollisions: [Collision]) {
        let currentPairs = Set(detectedCollisions.map { CollisionPair(bodyA: $0.bodyA, bodyB: $0.bodyB) })
        let previousPairs = collisionPairs

        // Enter: new collisions
        let entered = currentPairs.subtracting(previousPairs)
        for pair in entered {
            if let bodyA = physicsBodies[pair.bodyA],
               let bodyB = physicsBodies[pair.bodyB] {
                onCollisionEnter?(bodyA, bodyB)
                bodyA.onCollisionEnter?(bodyB)
                bodyB.onCollisionEnter?(bodyA)
            }
        }

        // Exit: ended collisions
        let exited = previousPairs.subtracting(currentPairs)
        for pair in exited {
            if let bodyA = physicsBodies[pair.bodyA],
               let bodyB = physicsBodies[pair.bodyB] {
                onCollisionExit?(bodyA, bodyB)
                bodyA.onCollisionExit?(bodyB)
                bodyB.onCollisionExit?(bodyA)
            }
        }

        // Stay: ongoing collisions
        let staying = currentPairs.intersection(previousPairs)
        for pair in staying {
            if let bodyA = physicsBodies[pair.bodyA],
               let bodyB = physicsBodies[pair.bodyB] {
                onCollisionStay?(bodyA, bodyB)
            }
        }

        collisionPairs = currentPairs
    }

    private func setupDefaultCollisionHandlers() {
        onCollisionEnter = { bodyA, bodyB in
            NotificationCenter.default.post(
                name: .physicsCollision,
                object: nil,
                userInfo: ["bodyA": bodyA, "bodyB": bodyB, "type": "enter"]
            )
        }
    }

    // MARK: - Helpers

    private func canCollide(_ bodyA: PhysicsBody, _ bodyB: PhysicsBody) -> Bool {
        // Check if collision layers are compatible
        return (bodyA.collisionLayer & bodyB.collisionMask) != 0 &&
               (bodyB.collisionLayer & bodyA.collisionMask) != 0
    }

    // MARK: - Raycasting

    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 100) -> RaycastHit? {
        var closestHit: RaycastHit?
        var closestDistance: Float = maxDistance

        for (_, body) in physicsBodies {
            guard body.detectCollisions else { continue }

            if let hit = raycastBody(origin: origin, direction: direction, body: body) {
                let distance = length(hit.point - origin)
                if distance < closestDistance {
                    closestDistance = distance
                    closestHit = hit
                }
            }
        }

        return closestHit
    }

    private func raycastBody(origin: SIMD3<Float>, direction: SIMD3<Float>, body: PhysicsBody) -> RaycastHit? {
        // Simplified sphere raycast
        switch body.colliderShape {
        case .sphere(let radius):
            return raycastSphere(origin: origin, direction: direction, center: body.position, radius: radius, body: body)
        default:
            // Fallback to bounding sphere
            return raycastSphere(origin: origin, direction: direction, center: body.position, radius: body.boundingRadius, body: body)
        }
    }

    private func raycastSphere(origin: SIMD3<Float>, direction: SIMD3<Float>,
                              center: SIMD3<Float>, radius: Float, body: PhysicsBody) -> RaycastHit? {
        let oc = origin - center
        let a = simd_dot(direction, direction)
        let b = 2.0 * simd_dot(oc, direction)
        let c = simd_dot(oc, oc) - radius * radius
        let discriminant = b * b - 4 * a * c

        if discriminant < 0 { return nil }

        let t = (-b - sqrt(discriminant)) / (2.0 * a)
        if t < 0 { return nil }

        let point = origin + direction * t
        let normal = normalize(point - center)

        return RaycastHit(
            body: body,
            point: point,
            normal: normal,
            distance: t
        )
    }
}

// MARK: - Supporting Types

struct CollisionPair: Hashable {
    let bodyA: UUID
    let bodyB: UUID

    init(bodyA: UUID, bodyB: UUID) {
        // Ensure consistent ordering for set operations
        if bodyA.uuidString < bodyB.uuidString {
            self.bodyA = bodyA
            self.bodyB = bodyB
        } else {
            self.bodyA = bodyB
            self.bodyB = bodyA
        }
    }
}

struct Collision {
    let bodyA: UUID
    let bodyB: UUID
    let contactPoint: SIMD3<Float>
    let normal: SIMD3<Float>
    let penetrationDepth: Float
}

struct RaycastHit {
    let body: PhysicsBody
    let point: SIMD3<Float>
    let normal: SIMD3<Float>
    let distance: Float
}

// MARK: - Notifications

extension Notification.Name {
    static let physicsBodyAdded = Notification.Name("physicsBodyAdded")
    static let physicsCollision = Notification.Name("physicsCollision")
}
