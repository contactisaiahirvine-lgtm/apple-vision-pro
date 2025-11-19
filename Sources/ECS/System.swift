import Foundation

/// System - Logic that operates on entities with specific components
/// Systems contain behavior, no data
@MainActor
protocol System {
    /// Unique identifier for this system
    var name: String { get }

    /// Priority for execution order (higher = earlier)
    var priority: Int { get }

    /// Called once when system is added
    func onAdd(to ecsManager: ECSManager)

    /// Called every frame
    func update(deltaTime: TimeInterval, ecsManager: ECSManager)

    /// Called when system is removed
    func onRemove(from ecsManager: ECSManager)
}

extension System {
    var priority: Int { return 0 }

    func onAdd(to ecsManager: ECSManager) {}
    func onRemove(from ecsManager: ECSManager) {}
}

// MARK: - Core Systems

/// Movement system - applies velocity to transform
@MainActor
class MovementSystem: System {
    let name = "MovementSystem"
    let priority = 10

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        let entities = ecsManager.entitiesWith([TransformComponent.self, VelocityComponent.self])

        for entity in entities {
            guard var transform: TransformComponent = ecsManager.getComponent(for: entity),
                  let velocity: VelocityComponent = ecsManager.getComponent(for: entity) else {
                continue
            }

            // Apply linear velocity
            transform.position += velocity.linear * Float(deltaTime)

            // Apply angular velocity (simplified rotation)
            if simd_length(velocity.angular) > 0.0001 {
                let angle = simd_length(velocity.angular) * Float(deltaTime)
                let axis = simd_normalize(velocity.angular)
                let rotation = simd_quatf(angle: angle, axis: axis)
                transform.rotation = rotation * transform.rotation
            }

            ecsManager.updateComponent(transform, for: entity)
        }
    }
}

/// Lifetime system - destroys entities after duration
@MainActor
class LifetimeSystem: System {
    let name = "LifetimeSystem"
    let priority = 5

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        let entities = ecsManager.entitiesWith([LifetimeComponent.self])

        for entity in entities {
            guard var lifetime: LifetimeComponent = ecsManager.getComponent(for: entity) else {
                continue
            }

            lifetime.remainingTime -= deltaTime

            if lifetime.remainingTime <= 0 {
                // Execute callback
                lifetime.onExpire?(entity)

                // Destroy entity
                ecsManager.destroyEntity(entity)
            } else {
                // Update component
                ecsManager.updateComponent(lifetime, for: entity)
            }
        }
    }
}

/// Health system - handles death
@MainActor
class HealthSystem: System {
    let name = "HealthSystem"
    let priority = 8

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        let entities = ecsManager.entitiesWith([HealthComponent.self])

        for entity in entities {
            guard let health: HealthComponent = ecsManager.getComponent(for: entity) else {
                continue
            }

            if health.isDead {
                // Execute death callback
                health.onDeath?(entity)

                // Destroy entity
                ecsManager.destroyEntity(entity)
            }
        }
    }
}

/// Hierarchy system - maintains parent-child relationships
@MainActor
class HierarchySystem: System {
    let name = "HierarchySystem"
    let priority = 15  // Run early

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        // Update children transforms based on parent
        let parents = ecsManager.entitiesWith([TransformComponent.self, ChildrenComponent.self])

        for parentEntity in parents {
            guard let parentTransform: TransformComponent = ecsManager.getComponent(for: parentEntity),
                  let children: ChildrenComponent = ecsManager.getComponent(for: parentEntity) else {
                continue
            }

            for childEntity in children.children {
                guard var childTransform: TransformComponent = ecsManager.getComponent(for: childEntity) else {
                    continue
                }

                // Calculate world transform
                let parentMatrix = parentTransform.matrix
                let childLocal = childTransform.matrix

                // This is simplified - in real implementation would decompose matrix
                // For now, just add parent position as offset
                childTransform.position = parentTransform.position + childTransform.position

                ecsManager.updateComponent(childTransform, for: childEntity)
            }
        }
    }
}

/// Physics sync system - syncs ECS physics with PhysicsManager
@MainActor
class PhysicsSyncSystem: System {
    let name = "PhysicsSyncSystem"
    let priority = 12

    weak var physicsManager: PhysicsManager?

    init(physicsManager: PhysicsManager?) {
        self.physicsManager = physicsManager
    }

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        guard let physicsManager = physicsManager else { return }

        let entities = ecsManager.entitiesWith([TransformComponent.self, PhysicsComponent.self])

        for entity in entities {
            guard var transform: TransformComponent = ecsManager.getComponent(for: entity),
                  let physics: PhysicsComponent = ecsManager.getComponent(for: entity),
                  let bodyID = physics.bodyID else {
                continue
            }

            // Find physics body
            if let physicsBody = physicsManager.bodies.first(where: { $0.id == bodyID }) {
                // Sync transform from physics
                transform.position = physicsBody.position
                transform.rotation = physicsBody.rotation

                ecsManager.updateComponent(transform, for: entity)
            }
        }
    }
}

/// Render sync system - syncs ECS with RealityKit entities
@MainActor
class RenderSyncSystem: System {
    let name = "RenderSyncSystem"
    let priority = 2  // Run late, after transforms updated

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        let entities = ecsManager.entitiesWith([TransformComponent.self, RenderableComponent.self])

        for entity in entities {
            guard let transform: TransformComponent = ecsManager.getComponent(for: entity),
                  let renderable: RenderableComponent = ecsManager.getComponent(for: entity),
                  let realityEntity = renderable.entity else {
                continue
            }

            // Update RealityKit entity transform
            realityEntity.position = transform.position
            realityEntity.orientation = transform.rotation
            realityEntity.scale = transform.scale

            // Update visibility
            realityEntity.isEnabled = renderable.isVisible
        }
    }
}
