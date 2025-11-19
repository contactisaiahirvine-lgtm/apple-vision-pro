import RealityKit
import SwiftUI

/// Factory for creating game entities
enum EntityFactory {
    /// Create a player entity with the specified configuration
    static func createPlayer(isLocal: Bool, position: SIMD3<Float> = .zero) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.2)
        var material = SimpleMaterial()
        material.color = .init(tint: isLocal ? .blue : .red)
        material.metallic = 0.8
        material.roughness = 0.2

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position

        // Add collision
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.2))])
        )

        // Add name tag
        entity.name = isLocal ? "LocalPlayer" : "RemotePlayer"

        return entity
    }

    /// Create a simple obstacle entity
    static func createObstacle(at position: SIMD3<Float>, size: Float = 0.5) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: size)
        var material = SimpleMaterial()
        material.color = .init(tint: .gray)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position

        // Add collision
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(size, size, size))])
        )

        return entity
    }

    /// Create a ground plane
    static func createGroundPlane(width: Float = 10, depth: Float = 10) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        var material = SimpleMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.1))
        material.roughness = 0.8

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position.y = 0

        return entity
    }

    /// Create a spawn point marker
    static func createSpawnPoint(at position: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.1)
        var material = SimpleMaterial()
        material.color = .init(tint: .green.withAlphaComponent(0.5))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position

        return entity
    }
}
