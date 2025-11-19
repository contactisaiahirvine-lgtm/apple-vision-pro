import Foundation
import RealityKit
import Combine

extension GameManager {
    /// Setup spatial tracking listeners
    func setupSpatialTrackingListeners(manager: SpatialTrackingManager) {
        // Listen for plane detection
        NotificationCenter.default.publisher(for: .planeDetected)
            .sink { [weak self] notification in
                guard let plane = notification.userInfo?["plane"] as? DetectedPlane else { return }
                self?.handlePlaneDetected(plane)
            }
            .store(in: &cancellables)

        // Listen for corner updates
        NotificationCenter.default.publisher(for: .cornersUpdated)
            .sink { [weak self] notification in
                guard let corners = notification.userInfo?["corners"] as? [DetectedCorner] else { return }
                self?.handleCornersUpdated(corners)
            }
            .store(in: &cancellables)
    }

    /// Handle newly detected plane
    private func handlePlaneDetected(_ plane: DetectedPlane) {
        guard isGameActive, let rootEntity = rootEntity else { return }

        // Visualize the plane if debug mode is enabled
        if GameConfig.enableDebugMode {
            let planeViz = SpatialVisualizer.createPlaneVisualization(
                for: plane,
                showBoundary: true,
                showFill: true
            )
            rootEntity.addChild(planeViz)
        }

        print("Game detected \(plane.classification.description) plane")

        // Game-specific logic based on plane type
        switch plane.classification {
        case .floor:
            // Could snap player to floor
            snapPlayerToFloor(plane)

        case .wall:
            // Could create collision boundaries
            createWallCollider(plane)

        case .table:
            // Could spawn items on tables
            spawnItemsOnSurface(plane)

        default:
            break
        }
    }

    /// Handle updated corners
    private func handleCornersUpdated(_ corners: [DetectedCorner]) {
        guard isGameActive, let rootEntity = rootEntity else { return }

        // Remove old corner visualizations
        rootEntity.children.forEach { child in
            if child.name.hasPrefix("corner_") {
                child.removeFromParent()
            }
        }

        // Visualize corners if debug mode is enabled
        if GameConfig.enableDebugMode {
            for corner in corners {
                let marker = SpatialVisualizer.createCornerMarker(for: corner)
                rootEntity.addChild(marker)
            }
        }

        print("Updated \(corners.count) corners")

        // Game-specific logic: could use corners for gameplay mechanics
        // Example: spawn power-ups at corners, create waypoints, etc.
    }

    // MARK: - Game-Specific Spatial Logic

    /// Snap player to detected floor plane
    private func snapPlayerToFloor(_ floor: DetectedPlane) {
        guard let localPlayer = localPlayer else { return }

        // Update player's Y position to floor level
        let floorY = floor.center.y
        localPlayer.position.y = floorY + GameConfig.playerSize

        print("Player snapped to floor at Y=\(floorY)")
    }

    /// Create collision geometry for walls
    private func createWallCollider(_ wall: DetectedPlane) {
        guard let rootEntity = rootEntity else { return }
        guard let geometry = wall.geometry else { return }

        // Create invisible collision mesh from wall geometry
        // This prevents players from walking through walls

        // For simplicity, create a plane collider
        let mesh = MeshResource.generatePlane(width: 2, depth: 2)
        let entity = ModelEntity(mesh: mesh, materials: [])

        // Make invisible
        entity.isEnabled = false

        // Add collision component
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(2, 2, 0.1))])
        )

        entity.transform.matrix = wall.transform
        entity.name = "wall_collider_\(wall.id)"

        rootEntity.addChild(entity)

        print("Created wall collider")
    }

    /// Spawn game items on horizontal surfaces
    private func spawnItemsOnSurface(_ surface: DetectedPlane) {
        guard surface.alignment == .horizontal else { return }
        guard let rootEntity = rootEntity else { return }

        // Example: spawn a collectible item on the surface
        let item = EntityFactory.createPowerUp(
            at: surface.center + SIMD3<Float>(0, 0.1, 0)
        )
        rootEntity.addChild(item)

        print("Spawned item on \(surface.classification.description)")
    }

    // MARK: - Spatial Queries

    /// Find the nearest floor plane to a position
    func findNearestFloor(to position: SIMD3<Float>, manager: SpatialTrackingManager) -> DetectedPlane? {
        let floors = manager.getHorizontalPlanes().filter { $0.classification == .floor }

        return floors.min { plane1, plane2 in
            distance(plane1.center, position) < distance(plane2.center, position)
        }
    }

    /// Check if position is near a wall
    func isNearWall(position: SIMD3<Float>, manager: SpatialTrackingManager, threshold: Float = 0.3) -> Bool {
        let walls = manager.getVerticalPlanes().filter { $0.classification == .wall }

        for wall in walls {
            let distToWall = abs(distance(wall.center, position) - 0.5) // Approximate
            if distToWall < threshold {
                return true
            }
        }

        return false
    }

    /// Find spawn points based on detected corners
    func findDynamicSpawnPoints(manager: SpatialTrackingManager) -> [SIMD3<Float>] {
        var spawnPoints: [SIMD3<Float>] = []

        // Use room corners as spawn points
        let corners = manager.detectedCorners

        // Filter corners that are at a reasonable height (near floor)
        let floorLevel = manager.getHorizontalPlanes()
            .filter { $0.classification == .floor }
            .first?.center.y ?? 0

        for corner in corners {
            // Corners near floor level make good spawn points
            if abs(corner.position.y - floorLevel) < 0.5 {
                // Offset slightly from the actual corner
                let offset = normalize(corner.normal) * 0.3
                spawnPoints.append(corner.position + offset)
            }
        }

        return spawnPoints
    }

    // MARK: - Visualization Helpers

    /// Toggle spatial tracking visualization
    func toggleSpatialVisualization(
        enabled: Bool,
        manager: SpatialTrackingManager
    ) {
        guard let rootEntity = rootEntity else { return }

        if enabled {
            // Show all planes and corners
            let debugViz = SpatialVisualizer.createDebugVisualization(
                planes: Array(manager.detectedPlanes.values),
                corners: manager.detectedCorners
            )
            debugViz.name = "spatial_debug_viz"
            rootEntity.addChild(debugViz)
        } else {
            // Remove visualization
            rootEntity.children.forEach { child in
                if child.name == "spatial_debug_viz" ||
                   child.name.hasPrefix("plane_") ||
                   child.name.hasPrefix("corner_") {
                    child.removeFromParent()
                }
            }
        }
    }
}

// MARK: - EntityFactory Extensions

extension EntityFactory {
    /// Create a power-up entity
    static func createPowerUp(at position: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.1)
        var material = SimpleMaterial()
        material.color = .init(tint: .systemYellow)
        material.metallic = 0.9
        material.roughness = 0.1

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.name = "powerup_\(UUID())"

        // Add collision for pickup detection
        entity.components.set(
            CollisionComponent(shapes: [.generateSphere(radius: 0.1)])
        )

        // Add rotation animation
        let rotation = FromToByAnimation(
            name: "rotate",
            from: Transform(rotation: simd_quatf(angle: 0, axis: [0, 1, 0])),
            to: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
            duration: 2.0,
            bindTarget: .transform
        )

        if let animation = try? AnimationResource.generate(with: rotation) {
            entity.playAnimation(animation.repeat())
        }

        return entity
    }
}
