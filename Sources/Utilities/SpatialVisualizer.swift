import RealityKit
import SwiftUI

/// Creates visual entities for detected planes and corners
enum SpatialVisualizer {

    // MARK: - Corner Visualization

    /// Create a visual marker for a detected corner
    static func createCornerMarker(
        for corner: DetectedCorner,
        color: UIColor = .systemBlue,
        size: Float = 0.05
    ) -> ModelEntity {
        // Create a small sphere at the corner
        let mesh = MeshResource.generateSphere(radius: size)
        var material = SimpleMaterial()
        material.color = .init(tint: color.withAlphaComponent(0.8))
        material.metallic = 0.5
        material.roughness = 0.2

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = corner.position
        entity.name = "corner_\(corner.id)"

        // Add a small cone pointing in the normal direction to show orientation
        let normalIndicator = createNormalIndicator(
            at: corner.position,
            normal: corner.normal,
            length: size * 2
        )
        entity.addChild(normalIndicator)

        return entity
    }

    /// Create an indicator showing the corner's normal direction
    private static func createNormalIndicator(
        at position: SIMD3<Float>,
        normal: SIMD3<Float>,
        length: Float
    ) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.005, length, 0.005))
        var material = SimpleMaterial()
        material.color = .init(tint: .yellow.withAlphaComponent(0.6))

        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Position the indicator along the normal
        entity.position = normal * (length / 2)

        // Rotate to align with normal
        if length(normal) > 0.001 {
            let up = SIMD3<Float>(0, 1, 0)
            let rotationAxis = cross(up, normal)
            if length(rotationAxis) > 0.001 {
                let angle = acos(simd_dot(up, normalize(normal)))
                entity.orientation = simd_quatf(angle: angle, axis: normalize(rotationAxis))
            }
        }

        return entity
    }

    // MARK: - Plane Visualization

    /// Create a visual representation of a detected plane
    static func createPlaneVisualization(
        for plane: DetectedPlane,
        showBoundary: Bool = true,
        showFill: Bool = true
    ) -> Entity {
        let container = Entity()
        container.name = "plane_\(plane.id)"

        // Add plane fill
        if showFill {
            let fill = createPlaneFill(for: plane)
            container.addChild(fill)
        }

        // Add boundary outline
        if showBoundary, let boundary = createPlaneBoundary(for: plane) {
            container.addChild(boundary)
        }

        // Add classification label (optional)
        if GameConfig.enableDebugMode {
            let label = createPlaneLabel(for: plane)
            container.addChild(label)
        }

        return container
    }

    /// Create a semi-transparent fill for the plane
    private static func createPlaneFill(for plane: DetectedPlane) -> ModelEntity {
        // Use a simple rectangle as placeholder
        // In production, you'd use the actual boundary geometry
        let mesh = MeshResource.generatePlane(width: 1, depth: 1)
        var material = SimpleMaterial()

        // Color based on plane type
        let color: UIColor = switch plane.classification {
        case .floor: .green
        case .wall: .blue
        case .ceiling: .cyan
        case .table: .orange
        case .door: .brown
        case .window: .clear
        default: .gray
        }

        material.color = .init(tint: color.withAlphaComponent(0.2))
        material.roughness = 0.8

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.transform.matrix = plane.transform

        return entity
    }

    /// Create a boundary outline for the plane
    private static func createPlaneBoundary(for plane: DetectedPlane) -> Entity? {
        guard let geometry = plane.geometry else { return nil }

        let container = Entity()

        // Create lines connecting boundary vertices
        let vertices = geometry.boundaryVertices
        guard vertices.count >= 3 else { return nil }

        for i in 0..<vertices.count {
            let v1 = vertices[i]
            let v2 = vertices[(i + 1) % vertices.count]

            // Transform 2D boundary points to 3D world space
            let p1_local = SIMD4<Float>(v1.x, 0, v1.y, 1)
            let p2_local = SIMD4<Float>(v2.x, 0, v2.y, 1)
            let p1_world = plane.transform * p1_local
            let p2_world = plane.transform * p2_local

            let p1 = SIMD3<Float>(p1_world.x, p1_world.y, p1_world.z)
            let p2 = SIMD3<Float>(p2_world.x, p2_world.y, p2_world.z)

            // Create line segment
            let line = createLineSegment(from: p1, to: p2, color: .systemYellow, thickness: 0.01)
            container.addChild(line)
        }

        return container
    }

    /// Create a 3D line segment between two points
    static func createLineSegment(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        color: UIColor = .white,
        thickness: Float = 0.005
    ) -> ModelEntity {
        let direction = end - start
        let length = simd_length(direction)
        let midpoint = (start + end) / 2

        // Create a thin cylinder as the line
        let mesh = MeshResource.generateBox(
            size: SIMD3<Float>(thickness, length, thickness)
        )
        var material = SimpleMaterial()
        material.color = .init(tint: color)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint

        // Rotate to align with direction
        if length > 0.001 {
            let up = SIMD3<Float>(0, 1, 0)
            let normalizedDirection = direction / length
            let rotationAxis = cross(up, normalizedDirection)

            if length(rotationAxis) > 0.001 {
                let angle = acos(simd_dot(up, normalizedDirection))
                entity.orientation = simd_quatf(angle: angle, axis: normalize(rotationAxis))
            }
        }

        return entity
    }

    /// Create a text label for the plane
    private static func createPlaneLabel(for plane: DetectedPlane) -> Entity {
        let label = Entity()
        label.position = plane.center + SIMD3<Float>(0, 0.1, 0)

        // Note: Text rendering in RealityKit requires TextMesh or custom implementation
        // This is a placeholder - actual implementation would use TextMesh

        return label
    }

    // MARK: - Corner Pattern Visualization

    /// Visualize corner patterns (e.g., room corners where 3 planes meet)
    static func visualizeRoomCorners(
        corners: [DetectedCorner],
        planes: [DetectedPlane]
    ) -> Entity {
        let container = Entity()

        // Group corners that are close together (room corners)
        let cornerGroups = groupNearbyCorners(corners, threshold: 0.15)

        for group in cornerGroups {
            // Room corners typically have 2+ corners close together
            if group.count >= 2 {
                let avgPosition = group.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(group.count)

                // Create a larger marker for room corners
                let marker = createCornerMarker(
                    for: group[0],
                    color: .systemRed,
                    size: 0.08
                )
                marker.position = avgPosition
                container.addChild(marker)
            }
        }

        return container
    }

    /// Group corners that are close to each other
    private static func groupNearbyCorners(
        _ corners: [DetectedCorner],
        threshold: Float
    ) -> [[DetectedCorner]] {
        var groups: [[DetectedCorner]] = []
        var processed: Set<UUID> = []

        for corner in corners {
            guard !processed.contains(corner.id) else { continue }

            var group = [corner]
            processed.insert(corner.id)

            // Find nearby corners
            for other in corners {
                guard !processed.contains(other.id) else { continue }

                if distance(corner.position, other.position) < threshold {
                    group.append(other)
                    processed.insert(other.id)
                }
            }

            groups.append(group)
        }

        return groups
    }

    // MARK: - Grid Visualization

    /// Create a reference grid on a plane
    static func createGridOnPlane(
        plane: DetectedPlane,
        gridSize: Float = 0.5,
        extent: Float = 5.0
    ) -> Entity {
        let container = Entity()

        let steps = Int(extent / gridSize)

        // Create grid lines
        for i in -steps...steps {
            let offset = Float(i) * gridSize

            // Lines along X axis
            let lineX = createLineSegment(
                from: SIMD3<Float>(-extent, 0, offset),
                to: SIMD3<Float>(extent, 0, offset),
                color: .white.withAlphaComponent(0.3),
                thickness: 0.002
            )

            // Lines along Z axis
            let lineZ = createLineSegment(
                from: SIMD3<Float>(offset, 0, -extent),
                to: SIMD3<Float>(offset, 0, extent),
                color: .white.withAlphaComponent(0.3),
                thickness: 0.002
            )

            container.addChild(lineX)
            container.addChild(lineZ)
        }

        // Apply plane transform
        container.transform.matrix = plane.transform

        return container
    }

    // MARK: - Debug Visualization

    /// Create comprehensive debug visualization
    static func createDebugVisualization(
        planes: [DetectedPlane],
        corners: [DetectedCorner]
    ) -> Entity {
        let container = Entity()

        // Visualize all planes
        for plane in planes {
            let planeViz = createPlaneVisualization(
                for: plane,
                showBoundary: true,
                showFill: true
            )
            container.addChild(planeViz)
        }

        // Visualize all corners
        for corner in corners {
            let color: UIColor = switch corner.type {
            case .planeBoundary: .systemBlue
            case .planeIntersection: .systemGreen
            }

            let marker = createCornerMarker(for: corner, color: color)
            container.addChild(marker)
        }

        return container
    }
}
