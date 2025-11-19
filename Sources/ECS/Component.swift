import Foundation
import RealityKit

/// Component - Data container attached to entities
/// Components hold data, no logic
protocol Component {
    /// Unique type identifier for this component
    static var typeID: String { get }
}

extension Component {
    static var typeID: String {
        return String(describing: Self.self)
    }
}

// MARK: - Core Components

/// Transform component - position, rotation, scale
struct TransformComponent: Component {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>

    init(position: SIMD3<Float> = .zero,
         rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
         scale: SIMD3<Float> = SIMD3(repeating: 1.0)) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    /// Get transformation matrix
    var matrix: float4x4 {
        let translation = float4x4(translation: position)
        let rotation = float4x4(rotation)
        let scale = float4x4(scale: scale)
        return translation * rotation * scale
    }
}

/// Renderable component - visual representation
struct RenderableComponent: Component {
    var entity: Entity?  // RealityKit entity
    var assetName: String
    var isVisible: Bool

    init(assetName: String, isVisible: Bool = true) {
        self.assetName = assetName
        self.isVisible = isVisible
    }
}

/// Physics component - physics body
struct PhysicsComponent: Component {
    var bodyID: UUID?  // Reference to PhysicsBody
    var mass: Float
    var isStatic: Bool
    var hasGravity: Bool

    init(mass: Float = 1.0, isStatic: Bool = false, hasGravity: Bool = true) {
        self.mass = mass
        self.isStatic = isStatic
        self.hasGravity = hasGravity
    }
}

/// Collision component - collision detection
struct CollisionComponent: Component {
    enum Shape {
        case sphere(radius: Float)
        case box(size: SIMD3<Float>)
        case capsule(height: Float, radius: Float)
    }

    var shape: Shape
    var isTrigger: Bool  // If true, doesn't cause physical collision

    init(shape: Shape, isTrigger: Bool = false) {
        self.shape = shape
        self.isTrigger = isTrigger
    }
}

/// Input target component - can receive input
struct InputTargetComponent: Component {
    var isInteractive: Bool
    var onTap: ((Entity) -> Void)?
    var onGaze: ((Entity, Bool) -> Void)?  // entity, isGazing

    init(isInteractive: Bool = true) {
        self.isInteractive = isInteractive
    }
}

/// Anchor component - tied to AR anchor
struct AnchorComponent: Component {
    var anchorID: UUID
    var anchorType: AnchorType

    enum AnchorType {
        case world
        case plane
        case image
        case object
    }

    init(anchorID: UUID, anchorType: AnchorType = .world) {
        self.anchorID = anchorID
        self.anchorType = anchorType
    }
}

/// Velocity component - movement
struct VelocityComponent: Component {
    var linear: SIMD3<Float>
    var angular: SIMD3<Float>

    init(linear: SIMD3<Float> = .zero, angular: SIMD3<Float> = .zero) {
        self.linear = linear
        self.angular = angular
    }
}

/// Audio source component - emits sound
struct AudioSourceComponent: Component {
    var audioFileName: String
    var isLooping: Bool
    var volume: Float
    var spatialBlend: Float  // 0.0 = 2D, 1.0 = 3D spatial

    init(audioFileName: String, isLooping: Bool = false,
         volume: Float = 1.0, spatialBlend: Float = 1.0) {
        self.audioFileName = audioFileName
        self.isLooping = isLooping
        self.volume = volume
        self.spatialBlend = spatialBlend
    }
}

/// Tag component - simple string tags for queries
struct TagComponent: Component {
    var tags: Set<String>

    init(tags: Set<String> = []) {
        self.tags = tags
    }

    init(tag: String) {
        self.tags = [tag]
    }

    mutating func add(_ tag: String) {
        tags.insert(tag)
    }

    mutating func remove(_ tag: String) {
        tags.remove(tag)
    }

    func has(_ tag: String) -> Bool {
        return tags.contains(tag)
    }
}

/// Lifetime component - destroy after duration
struct LifetimeComponent: Component {
    var remainingTime: TimeInterval
    var onExpire: ((Entity) -> Void)?

    init(duration: TimeInterval, onExpire: ((Entity) -> Void)? = nil) {
        self.remainingTime = duration
        self.onExpire = onExpire
    }
}

/// Health component - damage/health system
struct HealthComponent: Component {
    var current: Float
    var maximum: Float
    var onDeath: ((Entity) -> Void)?

    init(maximum: Float = 100.0, onDeath: ((Entity) -> Void)? = nil) {
        self.current = maximum
        self.maximum = maximum
        self.onDeath = onDeath
    }

    mutating func damage(_ amount: Float) {
        current = max(0, current - amount)
    }

    mutating func heal(_ amount: Float) {
        current = min(maximum, current + amount)
    }

    var isDead: Bool {
        return current <= 0
    }

    var healthPercentage: Float {
        return current / maximum
    }
}

/// Parent component - hierarchy
struct ParentComponent: Component {
    var parent: Entity

    init(parent: Entity) {
        self.parent = parent
    }
}

/// Children component - hierarchy
struct ChildrenComponent: Component {
    var children: [Entity]

    init(children: [Entity] = []) {
        self.children = children
    }

    mutating func add(_ child: Entity) {
        if !children.contains(child) {
            children.append(child)
        }
    }

    mutating func remove(_ child: Entity) {
        children.removeAll { $0 == child }
    }
}

// MARK: - Matrix Helpers

extension float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation.x, translation.y, translation.z, 1.0)
    }

    init(scale: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.0.x = scale.x
        columns.1.y = scale.y
        columns.2.z = scale.z
    }

    init(_ quaternion: simd_quatf) {
        self = float4x4(quaternion)
    }
}
