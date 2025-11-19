import Foundation
import RealityKit
import simd

/// Represents a physics-enabled body in the game world
class PhysicsBody: Identifiable, ObservableObject {
    let id = UUID()

    // Transform
    @Published var position: SIMD3<Float>
    @Published var rotation: simd_quatf
    @Published var scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)

    // Dynamics
    @Published var velocity: SIMD3<Float> = .zero
    @Published var angularVelocity: SIMD3<Float> = .zero

    // Forces (cleared each frame)
    var force: SIMD3<Float> = .zero
    var torque: SIMD3<Float> = .zero

    // Physical properties
    var mass: Float
    var momentOfInertia: Float  // Simplified scalar inertia
    var drag: Float = 0.1
    var angularDrag: Float = 0.05

    // Material
    var material: PhysicsMaterial

    // Collision
    var colliderShape: ColliderShape
    var detectCollisions: Bool = true
    var isTrigger: Bool = false  // Triggers don't resolve collisions physically

    // Collision layers (bit masks)
    var collisionLayer: UInt32 = PhysicsLayer.default.rawValue
    var collisionMask: UInt32 = PhysicsLayer.all.rawValue

    // Motion type
    var motionType: MotionType

    // Constraints
    var constraints: [PhysicsConstraint] = []
    var constrainedPosition: SIMD3<Float>

    // Settings
    var useGravity: Bool = true
    var maxVelocity: Float = 50.0
    var isKinematic: Bool = false  // Kinematic bodies are moved manually but affect dynamic bodies

    // Entity binding
    weak var entity: Entity?

    // Collision callbacks
    var onCollisionEnter: ((PhysicsBody) -> Void)?
    var onCollisionExit: ((PhysicsBody) -> Void)?

    // MARK: - Initialization

    init(
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        mass: Float = 1.0,
        colliderShape: ColliderShape = .sphere(radius: 0.5),
        material: PhysicsMaterial = .default,
        motionType: MotionType = .dynamic
    ) {
        self.position = position
        self.rotation = rotation
        self.mass = mass
        self.colliderShape = colliderShape
        self.material = material
        self.motionType = motionType
        self.constrainedPosition = position

        // Calculate moment of inertia based on shape
        self.momentOfInertia = Self.calculateMomentOfInertia(mass: mass, shape: colliderShape)
    }

    // MARK: - Computed Properties

    var isDynamic: Bool {
        return motionType == .dynamic && !isKinematic
    }

    var boundingRadius: Float {
        switch colliderShape {
        case .sphere(let radius):
            return radius
        case .box(let size):
            return length(size) * 0.5
        case .capsule(_, let radius):
            return radius
        }
    }

    // MARK: - Force Application

    func addForce(_ force: SIMD3<Float>) {
        self.force += force
    }

    func addImpulse(_ impulse: SIMD3<Float>) {
        velocity += impulse / mass
    }

    func addForceAtPoint(_ force: SIMD3<Float>, at point: SIMD3<Float>) {
        // Linear force
        self.force += force

        // Torque from offset
        let offset = point - position
        let torqueVector = cross(offset, force)
        self.torque += torqueVector
    }

    func addTorque(_ torque: SIMD3<Float>) {
        self.torque += torque
    }

    // MARK: - Movement

    func move(to newPosition: SIMD3<Float>) {
        position = newPosition
        constrainedPosition = newPosition
        updateEntityTransform()
    }

    func rotate(to newRotation: simd_quatf) {
        rotation = newRotation
        updateEntityTransform()
    }

    func teleport(to newPosition: SIMD3<Float>) {
        position = newPosition
        velocity = .zero
        angularVelocity = .zero
        force = .zero
        torque = .zero
        constrainedPosition = newPosition
        updateEntityTransform()
    }

    // MARK: - Entity Synchronization

    func updateEntityTransform() {
        guard let entity = entity else { return }

        var transform = Transform()
        transform.translation = position
        transform.rotation = rotation
        transform.scale = scale

        entity.transform = transform
    }

    func syncFromEntity() {
        guard let entity = entity else { return }

        position = entity.position
        rotation = entity.orientation
        scale = entity.scale
    }

    // MARK: - Helpers

    private static func calculateMomentOfInertia(mass: Float, shape: ColliderShape) -> Float {
        // Simplified moment of inertia calculations
        switch shape {
        case .sphere(let radius):
            // I = (2/5) * m * r^2
            return 0.4 * mass * radius * radius

        case .box(let size):
            // I = (1/12) * m * (w^2 + h^2) for a rectangular box
            let w = size.x
            let h = size.y
            return (1.0/12.0) * mass * (w*w + h*h)

        case .capsule(let height, let radius):
            // Approximate as cylinder
            return 0.5 * mass * radius * radius + (1.0/12.0) * mass * height * height
        }
    }

    // MARK: - Constraint Management

    func addConstraint(_ constraint: PhysicsConstraint) {
        constraints.append(constraint)

        // Store current position for frozen axes
        constrainedPosition = position
    }

    func removeConstraint(_ constraint: PhysicsConstraint) {
        constraints.removeAll { $0 == constraint }
    }
}

// MARK: - Enums and Supporting Types

enum ColliderShape: Equatable {
    case sphere(radius: Float)
    case box(size: SIMD3<Float>)
    case capsule(height: Float, radius: Float)

    static func == (lhs: ColliderShape, rhs: ColliderShape) -> Bool {
        switch (lhs, rhs) {
        case (.sphere(let r1), .sphere(let r2)):
            return r1 == r2
        case (.box(let s1), .box(let s2)):
            return s1 == s2
        case (.capsule(let h1, let r1), .capsule(let h2, let r2)):
            return h1 == h2 && r1 == r2
        default:
            return false
        }
    }
}

enum MotionType {
    case dynamic    // Affected by forces, collisions, and gravity
    case static     // Never moves, but affects dynamic bodies
    case kinematic  // Moved manually, affects dynamic bodies
}

enum PhysicsConstraint: Equatable {
    case freezePositionX
    case freezePositionY
    case freezePositionZ
    case freezeRotation
}

struct PhysicsMaterial {
    var friction: Float      // 0 = no friction, 1 = high friction
    var bounciness: Float    // 0 = no bounce, 1 = perfect bounce
    var density: Float       // kg/m³

    static let `default` = PhysicsMaterial(
        friction: 0.6,
        bounciness: 0.3,
        density: 1.0
    )

    static let ice = PhysicsMaterial(
        friction: 0.1,
        bounciness: 0.1,
        density: 0.9
    )

    static let rubber = PhysicsMaterial(
        friction: 0.8,
        bounciness: 0.9,
        density: 1.1
    )

    static let metal = PhysicsMaterial(
        friction: 0.4,
        bounciness: 0.5,
        density: 7.8
    )

    static let wood = PhysicsMaterial(
        friction: 0.5,
        bounciness: 0.2,
        density: 0.6
    )

    static let bouncy = PhysicsMaterial(
        friction: 0.3,
        bounciness: 0.95,
        density: 0.5
    )

    static let frictionless = PhysicsMaterial(
        friction: 0.0,
        bounciness: 0.0,
        density: 1.0
    )
}

struct PhysicsLayer: OptionSet {
    let rawValue: UInt32

    static let `default` = PhysicsLayer(rawValue: 1 << 0)
    static let player = PhysicsLayer(rawValue: 1 << 1)
    static let enemy = PhysicsLayer(rawValue: 1 << 2)
    static let projectile = PhysicsLayer(rawValue: 1 << 3)
    static let environment = PhysicsLayer(rawValue: 1 << 4)
    static let trigger = PhysicsLayer(rawValue: 1 << 5)
    static let item = PhysicsLayer(rawValue: 1 << 6)

    static let all: UInt32 = 0xFFFFFFFF
    static let none: UInt32 = 0
}

// MARK: - Physics Body Builder

extension PhysicsBody {
    /// Builder pattern for creating physics bodies
    class Builder {
        private var position: SIMD3<Float> = .zero
        private var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        private var mass: Float = 1.0
        private var colliderShape: ColliderShape = .sphere(radius: 0.5)
        private var material: PhysicsMaterial = .default
        private var motionType: MotionType = .dynamic
        private var useGravity: Bool = true
        private var isKinematic: Bool = false
        private var collisionLayer: UInt32 = PhysicsLayer.default.rawValue
        private var collisionMask: UInt32 = PhysicsLayer.all
        private var constraints: [PhysicsConstraint] = []

        func at(position: SIMD3<Float>) -> Builder {
            self.position = position
            return self
        }

        func withRotation(_ rotation: simd_quatf) -> Builder {
            self.rotation = rotation
            return self
        }

        func withMass(_ mass: Float) -> Builder {
            self.mass = mass
            return self
        }

        func withCollider(_ shape: ColliderShape) -> Builder {
            self.colliderShape = shape
            return self
        }

        func withMaterial(_ material: PhysicsMaterial) -> Builder {
            self.material = material
            return self
        }

        func asStatic() -> Builder {
            self.motionType = .static
            return self
        }

        func asKinematic() -> Builder {
            self.motionType = .kinematic
            self.isKinematic = true
            return self
        }

        func withGravity(_ enabled: Bool) -> Builder {
            self.useGravity = enabled
            return self
        }

        func onLayer(_ layer: UInt32) -> Builder {
            self.collisionLayer = layer
            return self
        }

        func collidingWith(_ mask: UInt32) -> Builder {
            self.collisionMask = mask
            return self
        }

        func withConstraints(_ constraints: [PhysicsConstraint]) -> Builder {
            self.constraints = constraints
            return self
        }

        func build() -> PhysicsBody {
            let body = PhysicsBody(
                position: position,
                rotation: rotation,
                mass: mass,
                colliderShape: colliderShape,
                material: material,
                motionType: motionType
            )

            body.useGravity = useGravity
            body.isKinematic = isKinematic
            body.collisionLayer = collisionLayer
            body.collisionMask = collisionMask
            body.constraints = constraints

            return body
        }
    }

    static func builder() -> Builder {
        return Builder()
    }
}
