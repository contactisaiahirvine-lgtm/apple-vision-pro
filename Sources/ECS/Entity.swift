import Foundation

/// Entity - A unique identifier for a game object
/// In ECS, entities are just IDs that tie components together
struct Entity: Hashable, Identifiable {
    let id: UUID

    init() {
        self.id = UUID()
    }

    init(id: UUID) {
        self.id = id
    }
}

/// Entity builder for convenient creation
class EntityBuilder {
    private let entity: Entity
    private weak var ecsManager: ECSManager?

    init(entity: Entity, ecsManager: ECSManager) {
        self.entity = entity
        self.ecsManager = ecsManager
    }

    @discardableResult
    func with<T: Component>(_ component: T) -> EntityBuilder {
        ecsManager?.addComponent(component, to: entity)
        return self
    }

    func build() -> Entity {
        return entity
    }
}
