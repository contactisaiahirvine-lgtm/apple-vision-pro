import Foundation
import RealityKit
import simd

/// Represents a player in the game
class Player: Identifiable, ObservableObject {
    let id: UUID
    let name: String
    var isLocal: Bool

    @Published var position: SIMD3<Float>
    @Published var rotation: simd_quatf
    @Published var velocity: SIMD3<Float>

    var entity: ModelEntity?

    init(id: UUID = UUID(), name: String, isLocal: Bool = false) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
        self.position = SIMD3<Float>(0, 0, 0)
        self.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        self.velocity = SIMD3<Float>(0, 0, 0)
    }

    /// Update player position based on velocity
    func updatePosition(deltaTime: Float) {
        // Apply velocity
        position += velocity * deltaTime

        // Apply friction
        let friction: Float = 0.9
        velocity *= friction

        // Update entity transform
        updateEntityTransform()
    }

    /// Move the player in a direction
    func move(direction: SIMD3<Float>, speed: Float = 2.0) {
        // SAFETY: Check for zero vector to prevent NaN
        let length = simd_length(direction)
        guard length > 0.001 else { return }

        let normalizedDirection = direction / length
        velocity += normalizedDirection * speed
    }

    /// Rotate the player
    func rotate(angle: Float, axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) {
        rotation = simd_quatf(angle: angle, axis: axis) * rotation
        updateEntityTransform()
    }

    /// Update the entity's transform to match the player's position and rotation
    func updateEntityTransform() {
        guard let entity = entity else { return }
        entity.transform.translation = position
        entity.transform.rotation = rotation
    }

    /// Serialize player data for network transmission
    func serialize() -> Data? {
        let playerData = PlayerNetworkData(
            id: id,
            name: name,
            position: position,
            rotation: rotation,
            velocity: velocity
        )
        return try? JSONEncoder().encode(playerData)
    }

    /// Update player from network data
    func update(from data: PlayerNetworkData) {
        position = data.position
        rotation = data.rotation
        velocity = data.velocity
        updateEntityTransform()
    }
}

/// Network-serializable player data
struct PlayerNetworkData: Codable {
    let id: UUID
    let name: String
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let velocity: SIMD3<Float>

    enum CodingKeys: String, CodingKey {
        case id, name, position, rotation, velocity
    }

    init(id: UUID, name: String, position: SIMD3<Float>, rotation: simd_quatf, velocity: SIMD3<Float>) {
        self.id = id
        self.name = name
        self.position = position
        self.rotation = rotation
        self.velocity = velocity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let posArray = try container.decode([Float].self, forKey: .position)
        position = SIMD3<Float>(posArray[0], posArray[1], posArray[2])

        let rotArray = try container.decode([Float].self, forKey: .rotation)
        rotation = simd_quatf(ix: rotArray[0], iy: rotArray[1], iz: rotArray[2], r: rotArray[3])

        let velArray = try container.decode([Float].self, forKey: .velocity)
        velocity = SIMD3<Float>(velArray[0], velArray[1], velArray[2])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode([position.x, position.y, position.z], forKey: .position)
        try container.encode([rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real], forKey: .rotation)
        try container.encode([velocity.x, velocity.y, velocity.z], forKey: .velocity)
    }
}
