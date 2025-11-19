import Foundation
import Combine

/// ECS Manager - Central coordinator for entities, components, and systems
@MainActor
class ECSManager: ObservableObject {

    // MARK: - Properties

    @Published var entityCount: Int = 0
    @Published var systemCount: Int = 0

    private var entities: Set<Entity> = []
    private var components: [String: [Entity: Any]] = [:]  // componentType -> [entity: component]
    private var systems: [System] = []

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        print("ECSManager initialized")
    }

    // MARK: - Entity Management

    /// Create a new entity
    func createEntity() -> Entity {
        let entity = Entity()
        entities.insert(entity)
        entityCount = entities.count

        NotificationCenter.default.post(name: .entityCreated, object: nil, userInfo: ["entity": entity])

        return entity
    }

    /// Create entity with builder pattern
    func createEntity(configure: (EntityBuilder) -> Void) -> Entity {
        let entity = createEntity()
        let builder = EntityBuilder(entity: entity, ecsManager: self)
        configure(builder)
        return entity
    }

    /// Destroy an entity and all its components
    func destroyEntity(_ entity: Entity) {
        // Remove all components
        for (componentType, _) in components {
            components[componentType]?[entity] = nil
        }

        // Remove entity
        entities.remove(entity)
        entityCount = entities.count

        NotificationCenter.default.post(name: .entityDestroyed, object: nil, userInfo: ["entity": entity])
    }

    /// Check if entity exists
    func entityExists(_ entity: Entity) -> Bool {
        return entities.contains(entity)
    }

    /// Get all entities
    func getAllEntities() -> [Entity] {
        return Array(entities)
    }

    // MARK: - Component Management

    /// Add a component to an entity
    func addComponent<T: Component>(_ component: T, to entity: Entity) {
        let typeID = T.typeID

        if components[typeID] == nil {
            components[typeID] = [:]
        }

        components[typeID]?[entity] = component

        NotificationCenter.default.post(
            name: .componentAdded,
            object: nil,
            userInfo: ["entity": entity, "componentType": typeID]
        )
    }

    /// Get a component from an entity
    func getComponent<T: Component>(for entity: Entity) -> T? {
        let typeID = T.typeID
        return components[typeID]?[entity] as? T
    }

    /// Update a component for an entity
    func updateComponent<T: Component>(_ component: T, for entity: Entity) {
        let typeID = T.typeID
        components[typeID]?[entity] = component
    }

    /// Remove a component from an entity
    func removeComponent<T: Component>(ofType type: T.Type, from entity: Entity) {
        let typeID = T.typeID
        components[typeID]?[entity] = nil

        NotificationCenter.default.post(
            name: .componentRemoved,
            object: nil,
            userInfo: ["entity": entity, "componentType": typeID]
        )
    }

    /// Check if entity has a component
    func hasComponent<T: Component>(entity: Entity, ofType type: T.Type) -> Bool {
        let typeID = T.typeID
        return components[typeID]?[entity] != nil
    }

    /// Get all entities with specific components
    func entitiesWith<T: Component>(_ componentType: T.Type) -> [Entity] {
        let typeID = T.typeID
        guard let componentMap = components[typeID] else { return [] }

        return Array(componentMap.keys)
    }

    /// Get all entities with multiple specific components
    func entitiesWith(_ componentTypes: [Any.Type]) -> [Entity] {
        // Get type IDs
        let typeIDs = componentTypes.map { type -> String in
            if let componentType = type as? Component.Type {
                return componentType.typeID
            }
            return String(describing: type)
        }

        // Start with all entities
        var result = entities

        // Filter to entities that have ALL required components
        for typeID in typeIDs {
            guard let componentMap = components[typeID] else {
                return []  // If component type doesn't exist, no entities have it
            }

            let entitiesWithComponent = Set(componentMap.keys)
            result = result.intersection(entitiesWithComponent)
        }

        return Array(result)
    }

    /// Get all components of a type
    func getAllComponents<T: Component>(ofType type: T.Type) -> [(Entity, T)] {
        let typeID = T.typeID
        guard let componentMap = components[typeID] else { return [] }

        return componentMap.compactMap { (entity, component) in
            if let typedComponent = component as? T {
                return (entity, typedComponent)
            }
            return nil
        }
    }

    // MARK: - System Management

    /// Add a system
    func addSystem(_ system: System) {
        systems.append(system)
        systems.sort { $0.priority > $1.priority }  // Higher priority runs first
        systemCount = systems.count

        system.onAdd(to: self)

        print("Added system: \(system.name) (priority: \(system.priority))")
    }

    /// Remove a system
    func removeSystem(named name: String) {
        if let index = systems.firstIndex(where: { $0.name == name }) {
            let system = systems[index]
            system.onRemove(from: self)
            systems.remove(at: index)
            systemCount = systems.count
            print("Removed system: \(name)")
        }
    }

    /// Get system by name
    func getSystem<T: System>(ofType type: T.Type) -> T? {
        return systems.first { $0 is T } as? T
    }

    /// Update all systems
    func update(deltaTime: TimeInterval) {
        for system in systems {
            system.update(deltaTime: deltaTime, ecsManager: self)
        }
    }

    // MARK: - Query Helpers

    /// Find entities with specific tag
    func entitiesWithTag(_ tag: String) -> [Entity] {
        let taggedEntities = entitiesWith(TagComponent.self)

        return taggedEntities.filter { entity in
            if let tagComponent: TagComponent = getComponent(for: entity) {
                return tagComponent.has(tag)
            }
            return false
        }
    }

    /// Find entities within radius of position
    func entitiesNear(position: SIMD3<Float>, radius: Float) -> [Entity] {
        let entities = entitiesWith(TransformComponent.self)

        return entities.filter { entity in
            if let transform: TransformComponent = getComponent(for: entity) {
                let distance = simd_distance(position, transform.position)
                return distance <= radius
            }
            return false
        }
    }

    /// Find closest entity to position
    func closestEntity(to position: SIMD3<Float>, withTag tag: String? = nil) -> Entity? {
        var candidates = entitiesWith(TransformComponent.self)

        // Filter by tag if specified
        if let tag = tag {
            candidates = candidates.filter { entity in
                if let tagComponent: TagComponent = getComponent(for: entity) {
                    return tagComponent.has(tag)
                }
                return false
            }
        }

        var closestEntity: Entity?
        var closestDistance: Float = .infinity

        for entity in candidates {
            if let transform: TransformComponent = getComponent(for: entity) {
                let distance = simd_distance(position, transform.position)
                if distance < closestDistance {
                    closestDistance = distance
                    closestEntity = entity
                }
            }
        }

        return closestEntity
    }

    // MARK: - Debugging

    /// Get statistics
    func getStatistics() -> ECSStatistics {
        var componentCounts: [String: Int] = [:]

        for (typeID, componentMap) in components {
            componentCounts[typeID] = componentMap.count
        }

        return ECSStatistics(
            entityCount: entities.count,
            systemCount: systems.count,
            componentCounts: componentCounts
        )
    }

    /// Print debug info
    func printDebugInfo() {
        print("=== ECS Debug Info ===")
        print("Entities: \(entities.count)")
        print("Systems: \(systems.count)")
        print("Components:")
        for (typeID, componentMap) in components {
            print("  \(typeID): \(componentMap.count)")
        }
        print("=====================")
    }
}

// MARK: - Statistics

struct ECSStatistics {
    let entityCount: Int
    let systemCount: Int
    let componentCounts: [String: Int]

    var totalComponents: Int {
        return componentCounts.values.reduce(0, +)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let entityCreated = Notification.Name("entityCreated")
    static let entityDestroyed = Notification.Name("entityDestroyed")
    static let componentAdded = Notification.Name("componentAdded")
    static let componentRemoved = Notification.Name("componentRemoved")
}
