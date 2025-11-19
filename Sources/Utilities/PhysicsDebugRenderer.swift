import RealityKit
import SwiftUI

/// Renders debug visualizations for physics bodies and collisions
enum PhysicsDebugRenderer {

    // MARK: - Physics Body Visualization

    /// Create debug visualization for a physics body
    static func createBodyDebugVisualization(for body: PhysicsBody) -> Entity {
        let container = Entity()
        container.name = "physics_debug_\(body.id)"

        // Collider outline
        let colliderViz = createColliderVisualization(for: body)
        container.addChild(colliderViz)

        // Velocity arrow
        if length(body.velocity) > 0.1 {
            let velocityArrow = createVelocityArrow(from: body.position, velocity: body.velocity)
            container.addChild(velocityArrow)
        }

        // Center of mass marker
        let centerMarker = createCenterOfMassMarker(at: body.position)
        container.addChild(centerMarker)

        return container
    }

    /// Create collider shape outline
    private static func createColliderVisualization(for body: PhysicsBody) -> ModelEntity {
        let mesh: MeshResource
        var material = SimpleMaterial()

        // Color based on motion type
        let color: UIColor = switch body.motionType {
        case .dynamic: .systemGreen
        case .static: .systemRed
        case .kinematic: .systemYellow
        }

        material.color = .init(tint: color.withAlphaComponent(0.3))
        material.roughness = 1.0

        switch body.colliderShape {
        case .sphere(let radius):
            mesh = MeshResource.generateSphere(radius: radius)

        case .box(let size):
            mesh = MeshResource.generateBox(size: size)

        case .capsule(let height, let radius):
            // Approximate with box for now
            mesh = MeshResource.generateBox(size: SIMD3<Float>(radius * 2, height, radius * 2))
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = body.position
        entity.orientation = body.rotation

        return entity
    }

    /// Create velocity arrow
    private static func createVelocityArrow(from position: SIMD3<Float>, velocity: SIMD3<Float>) -> Entity {
        let container = Entity()

        let speed = length(velocity)
        let direction = normalize(velocity)

        // Arrow shaft
        let shaft = createLine(
            from: position,
            to: position + direction * min(speed * 0.1, 2.0),
            color: .systemBlue,
            thickness: 0.02
        )
        container.addChild(shaft)

        return container
    }

    /// Create center of mass marker
    private static func createCenterOfMassMarker(at position: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.03)
        var material = SimpleMaterial()
        material.color = .init(tint: .white)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position

        return entity
    }

    /// Create a line between two points
    private static func createLine(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        color: UIColor,
        thickness: Float = 0.01
    ) -> ModelEntity {
        let direction = end - start
        let length = simd_length(direction)
        let midpoint = (start + end) / 2

        let mesh = MeshResource.generateBox(size: SIMD3<Float>(thickness, length, thickness))
        var material = SimpleMaterial()
        material.color = .init(tint: color)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint

        // Rotate to align with direction
        if length > 0.001 {
            let up = SIMD3<Float>(0, 1, 0)
            let normalizedDirection = direction / length
            let rotationAxis = cross(up, normalizedDirection)

            if simd_length(rotationAxis) > 0.001 {
                let angle = acos(simd_dot(up, normalizedDirection))
                entity.orientation = simd_quatf(angle: angle, axis: normalize(rotationAxis))
            }
        }

        return entity
    }

    // MARK: - Collision Visualization

    /// Create visualization for a collision contact point
    static func createCollisionVisualization(
        at point: SIMD3<Float>,
        normal: SIMD3<Float>,
        penetration: Float
    ) -> Entity {
        let container = Entity()

        // Contact point marker
        let marker = createContactMarker(at: point)
        container.addChild(marker)

        // Normal arrow
        let normalArrow = createLine(
            from: point,
            to: point + normal * 0.2,
            color: .systemRed,
            thickness: 0.015
        )
        container.addChild(normalArrow)

        // Penetration indicator
        if penetration > 0.01 {
            let penetrationViz = createPenetrationVisualization(
                at: point,
                normal: normal,
                depth: penetration
            )
            container.addChild(penetrationViz)
        }

        return container
    }

    private static func createContactMarker(at position: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.04)
        var material = SimpleMaterial()
        material.color = .init(tint: .systemRed)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position

        return entity
    }

    private static func createPenetrationVisualization(
        at point: SIMD3<Float>,
        normal: SIMD3<Float>,
        depth: Float
    ) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.01, depth, 0.01))
        var material = SimpleMaterial()
        material.color = .init(tint: .systemOrange.withAlphaComponent(0.5))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = point - normal * depth * 0.5

        return entity
    }

    // MARK: - Force Visualization

    /// Visualize applied forces on a body
    static func createForceVisualization(
        for body: PhysicsBody,
        showForce: Bool = true,
        showTorque: Bool = true
    ) -> Entity {
        let container = Entity()

        // Force arrow
        if showForce && length(body.force) > 0.01 {
            let forceArrow = createLine(
                from: body.position,
                to: body.position + normalize(body.force) * 0.5,
                color: .systemPurple,
                thickness: 0.02
            )
            container.addChild(forceArrow)
        }

        // Torque visualization (circular arrow)
        if showTorque && length(body.torque) > 0.01 {
            // Simplified: just show direction
            let torqueIndicator = createLine(
                from: body.position,
                to: body.position + normalize(body.torque) * 0.3,
                color: .systemPink,
                thickness: 0.015
            )
            container.addChild(torqueIndicator)
        }

        return container
    }

    // MARK: - Comprehensive Debug View

    /// Create complete debug visualization for physics system
    static func createPhysicsDebugView(
        physicsManager: PhysicsManager,
        showBodies: Bool = true,
        showVelocities: Bool = true,
        showForces: Bool = false
    ) -> Entity {
        let container = Entity()
        container.name = "physics_debug_view"

        for (_, body) in physicsManager.physicsBodies {
            if showBodies {
                let bodyViz = createBodyDebugVisualization(for: body)
                container.addChild(bodyViz)
            }

            if showForces && (length(body.force) > 0.01 || length(body.torque) > 0.01) {
                let forceViz = createForceVisualization(for: body)
                container.addChild(forceViz)
            }
        }

        return container
    }

    // MARK: - Raycast Visualization

    /// Visualize a raycast
    static func createRaycastVisualization(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistance: Float,
        hit: RaycastHit? = nil
    ) -> Entity {
        let container = Entity()

        let endPoint = hit?.point ?? (origin + direction * maxDistance)

        // Ray line
        let rayLine = createLine(
            from: origin,
            to: endPoint,
            color: hit != nil ? .systemGreen : .systemGray,
            thickness: 0.01
        )
        container.addChild(rayLine)

        // Hit point marker
        if let hit = hit {
            let hitMarker = createContactMarker(at: hit.point)
            container.addChild(hitMarker)

            // Hit normal
            let normalLine = createLine(
                from: hit.point,
                to: hit.point + hit.normal * 0.2,
                color: .systemYellow,
                thickness: 0.008
            )
            container.addChild(normalLine)
        }

        return container
    }

    // MARK: - Grid and Bounds

    /// Create physics bounds visualization
    static func createBoundsVisualization(
        min: SIMD3<Float>,
        max: SIMD3<Float>
    ) -> Entity {
        let container = Entity()
        let center = (min + max) * 0.5
        let size = max - min

        let mesh = MeshResource.generateBox(size: size)
        var material = SimpleMaterial()
        material.color = .init(tint: .systemBlue.withAlphaComponent(0.1))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = center

        container.addChild(entity)

        return entity
    }
}
