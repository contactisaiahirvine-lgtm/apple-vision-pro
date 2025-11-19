import Foundation
import simd

/// Global game configuration
enum GameConfig {
    // MARK: - Player Settings
    static let defaultPlayerSpeed: Float = 2.0
    static let maxPlayerSpeed: Float = 5.0
    static let jumpForce: Float = 3.0
    static let playerSize: Float = 0.2
    static let playerFriction: Float = 0.9

    // MARK: - World Settings
    static let groundLevel: Float = -0.5
    static let worldBoundsMin = SIMD3<Float>(-5, -1, -5)
    static let worldBoundsMax = SIMD3<Float>(5, 5, 5)
    static let gravity = SIMD3<Float>(0, -9.8, 0)

    // MARK: - Network Settings
    static let maxPlayers = 8
    static let networkUpdateRate: TimeInterval = 0.033 // ~30 updates per second
    static let connectionTimeout: TimeInterval = 30.0

    // MARK: - Game Settings
    static let targetFrameRate = 60
    static let enableDebugMode = true

    // MARK: - Spawn Points
    static let spawnPoints: [SIMD3<Float>] = [
        SIMD3<Float>(0, 1, -2),
        SIMD3<Float>(2, 1, -2),
        SIMD3<Float>(-2, 1, -2),
        SIMD3<Float>(0, 1, -4),
        SIMD3<Float>(2, 1, -4),
        SIMD3<Float>(-2, 1, -4)
    ]

    /// Get a random spawn point
    static func randomSpawnPoint() -> SIMD3<Float> {
        spawnPoints.randomElement() ?? SIMD3<Float>(0, 1, -2)
    }

    /// Clamp position within world bounds
    static func clampPosition(_ position: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            max(worldBoundsMin.x, min(worldBoundsMax.x, position.x)),
            max(worldBoundsMin.y, min(worldBoundsMax.y, position.y)),
            max(worldBoundsMin.z, min(worldBoundsMax.z, position.z))
        )
    }
}
