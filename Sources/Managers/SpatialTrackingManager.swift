import Foundation
import ARKit
import RealityKit
import SwiftUI

/// Manages spatial tracking, plane detection, and corner recognition for visionOS
@MainActor
class SpatialTrackingManager: ObservableObject {
    @Published var detectedPlanes: [UUID: DetectedPlane] = [:]
    @Published var detectedCorners: [DetectedCorner] = []
    @Published var isTrackingActive = false

    private var planeDetectionProvider: PlaneDetectionProvider?
    private var sceneReconstructionProvider: SceneReconstructionProvider?
    private var worldTrackingProvider: WorldTrackingProvider?

    private var arkitSession = ARKitSession()
    private var trackingTask: Task<Void, Never>?

    // Configuration
    private let planeDetectionConfig = PlaneDetectionProvider.Configuration(
        alignments: [.horizontal, .vertical]
    )

    private let sceneReconstructionConfig = SceneReconstructionProvider.Configuration()

    // MARK: - Lifecycle

    init() {
        setupProviders()
    }

    private func setupProviders() {
        planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
        sceneReconstructionProvider = SceneReconstructionProvider()
        worldTrackingProvider = WorldTrackingProvider()
    }

    // MARK: - Session Management

    func startTracking() async {
        guard !isTrackingActive else { return }

        do {
            // Request authorization
            let authorizationResult = await arkitSession.requestAuthorization(for: [
                .worldSensing,
                .planeDetection,
                .sceneReconstruction
            ])

            guard authorizationResult[.worldSensing] == .allowed,
                  authorizationResult[.planeDetection] == .allowed else {
                print("Required permissions not granted")
                return
            }

            // Start ARKit session
            guard let planeProvider = planeDetectionProvider,
                  let sceneProvider = sceneReconstructionProvider else {
                print("Providers not initialized")
                return
            }

            try await arkitSession.run([planeProvider, sceneProvider])

            isTrackingActive = true
            print("Spatial tracking started")

            // Start processing updates
            await processUpdates()

        } catch {
            print("Failed to start spatial tracking: \(error)")
        }
    }

    func stopTracking() {
        trackingTask?.cancel()
        arkitSession.stop()
        isTrackingActive = false
        detectedPlanes.removeAll()
        detectedCorners.removeAll()
        print("Spatial tracking stopped")
    }

    // MARK: - Update Processing

    private func processUpdates() async {
        guard let planeProvider = planeDetectionProvider else { return }

        trackingTask = Task {
            for await update in planeProvider.anchorUpdates {
                switch update.event {
                case .added:
                    await handlePlaneAdded(update.anchor)
                case .updated:
                    await handlePlaneUpdated(update.anchor)
                case .removed:
                    await handlePlaneRemoved(update.anchor)
                }
            }
        }
    }

    // MARK: - Plane Handling

    private func handlePlaneAdded(_ anchor: PlaneAnchor) async {
        let plane = DetectedPlane(anchor: anchor)
        detectedPlanes[anchor.id] = plane

        print("Plane added: \(anchor.classification.description) at \(anchor.originFromAnchorTransform.columns.3)")

        // Update corners based on new plane
        await updateCorners()

        // Notify observers
        NotificationCenter.default.post(
            name: .planeDetected,
            object: nil,
            userInfo: ["plane": plane]
        )
    }

    private func handlePlaneUpdated(_ anchor: PlaneAnchor) async {
        if let existingPlane = detectedPlanes[anchor.id] {
            existingPlane.update(from: anchor)

            // Update corners when planes change
            await updateCorners()
        }
    }

    private func handlePlaneRemoved(_ anchor: PlaneAnchor) async {
        detectedPlanes.removeValue(forKey: anchor.id)

        // Update corners after plane removal
        await updateCorners()

        print("Plane removed: \(anchor.id)")
    }

    // MARK: - Corner Detection

    /// Detect corners from plane boundaries and intersections
    private func updateCorners() async {
        var corners: [DetectedCorner] = []

        // Method 1: Extract corners from plane boundaries
        for plane in detectedPlanes.values {
            let boundaryCorners = extractCornersFromBoundary(plane)
            corners.append(contentsOf: boundaryCorners)
        }

        // Method 2: Find corners at plane intersections
        let intersectionCorners = findPlaneIntersectionCorners()
        corners.append(contentsOf: intersectionCorners)

        // Remove duplicates (corners within 5cm of each other)
        corners = removeDuplicateCorners(corners, threshold: 0.05)

        // Update published property
        self.detectedCorners = corners

        // Notify observers
        NotificationCenter.default.post(
            name: .cornersUpdated,
            object: nil,
            userInfo: ["corners": corners]
        )

        print("Updated corners: \(corners.count) detected")
    }

    /// Extract corner points from a plane's boundary
    private func extractCornersFromBoundary(_ plane: DetectedPlane) -> [DetectedCorner] {
        var corners: [DetectedCorner] = []

        guard let geometry = plane.geometry else { return corners }

        // Plane boundaries are provided as 2D points, transform to 3D
        let transform = plane.transform

        for vertex in geometry.boundaryVertices {
            // Convert 2D boundary point to 3D world position
            let localPoint = SIMD4<Float>(vertex.x, 0, vertex.y, 1)
            let worldPoint = transform * localPoint
            let position = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)

            let corner = DetectedCorner(
                position: position,
                normal: plane.normal,
                type: .planeBoundary,
                associatedPlanes: [plane.id]
            )
            corners.append(corner)
        }

        return corners
    }

    /// Find corners where planes intersect
    private func findPlaneIntersectionCorners() -> [DetectedCorner] {
        var corners: [DetectedCorner] = []
        let planes = Array(detectedPlanes.values)

        // Check each pair of planes for intersections
        for i in 0..<planes.count {
            for j in (i+1)..<planes.count {
                let plane1 = planes[i]
                let plane2 = planes[j]

                // Check if planes are perpendicular (walls meeting floor, wall corners, etc.)
                if arePlanesIntersecting(plane1, plane2) {
                    if let intersectionCorners = calculateIntersectionCorners(plane1, plane2) {
                        corners.append(contentsOf: intersectionCorners)
                    }
                }
            }
        }

        return corners
    }

    /// Check if two planes are likely to intersect (not parallel)
    private func arePlanesIntersecting(_ plane1: DetectedPlane, plane2: DetectedPlane) -> Bool {
        let dotProduct = abs(simd_dot(plane1.normal, plane2.normal))
        // Planes are intersecting if they're not parallel (dot product not close to 1)
        return dotProduct < 0.95
    }

    /// Calculate corner points where two planes intersect
    private func calculateIntersectionCorners(_ plane1: DetectedPlane, plane2: DetectedPlane) -> [DetectedCorner]? {
        var corners: [DetectedCorner] = []

        // Get the line of intersection between the two planes
        guard let intersectionLine = calculatePlaneIntersectionLine(plane1, plane2) else {
            return nil
        }

        // Find where this line intersects the boundaries of both planes
        let points = findLineIntersectionWithBoundaries(
            line: intersectionLine,
            planes: [plane1, plane2]
        )

        for point in points {
            // Calculate corner normal (average of plane normals)
            let normal = normalize(plane1.normal + plane2.normal)

            let corner = DetectedCorner(
                position: point,
                normal: normal,
                type: .planeIntersection,
                associatedPlanes: [plane1.id, plane2.id]
            )
            corners.append(corner)
        }

        return corners.isEmpty ? nil : corners
    }

    /// Calculate the line where two planes intersect
    private func calculatePlaneIntersectionLine(_ plane1: DetectedPlane, plane2: DetectedPlane) -> IntersectionLine? {
        let n1 = plane1.normal
        let n2 = plane2.normal

        // Direction of intersection line is perpendicular to both normals
        let direction = cross(n1, n2)

        // If cross product is zero, planes are parallel
        guard length(direction) > 0.001 else { return nil }

        // Find a point on the line
        let p1 = plane1.center
        let p2 = plane2.center

        // Use the midpoint between plane centers projected onto the intersection line
        let midpoint = (p1 + p2) * 0.5

        return IntersectionLine(point: midpoint, direction: normalize(direction))
    }

    /// Find where a line intersects plane boundaries
    private func findLineIntersectionWithBoundaries(line: IntersectionLine, planes: [DetectedPlane]) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []

        for plane in planes {
            guard let geometry = plane.geometry else { continue }

            let transform = plane.transform

            // Check intersection with each boundary edge
            let vertices = geometry.boundaryVertices
            for i in 0..<vertices.count {
                let v1 = vertices[i]
                let v2 = vertices[(i + 1) % vertices.count]

                // Transform to 3D world space
                let p1_local = SIMD4<Float>(v1.x, 0, v1.y, 1)
                let p2_local = SIMD4<Float>(v2.x, 0, v2.y, 1)
                let p1_world = transform * p1_local
                let p2_world = transform * p2_local

                let p1 = SIMD3<Float>(p1_world.x, p1_world.y, p1_world.z)
                let p2 = SIMD3<Float>(p2_world.x, p2_world.y, p2_world.z)

                // Find closest point between line and edge
                if let intersection = closestPointBetweenLines(
                    line1Start: line.point,
                    line1Direction: line.direction,
                    line2Start: p1,
                    line2Direction: normalize(p2 - p1)
                ) {
                    // Verify point is actually on the edge segment
                    if isPointOnSegment(intersection, start: p1, end: p2, threshold: 0.1) {
                        points.append(intersection)
                    }
                }
            }
        }

        return points
    }

    /// Find closest point between two 3D lines
    private func closestPointBetweenLines(
        line1Start: SIMD3<Float>,
        line1Direction: SIMD3<Float>,
        line2Start: SIMD3<Float>,
        line2Direction: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let cross12 = cross(line1Direction, line2Direction)
        let crossLength = length(cross12)

        guard crossLength > 0.001 else { return nil } // Lines are parallel

        let diff = line2Start - line1Start
        let t = simd_dot(cross(diff, line2Direction), cross12) / (crossLength * crossLength)

        return line1Start + line1Direction * t
    }

    /// Check if a point lies on a line segment
    private func isPointOnSegment(_ point: SIMD3<Float>, start: SIMD3<Float>, end: SIMD3<Float>, threshold: Float) -> Bool {
        let segmentLength = distance(start, end)
        let distFromStart = distance(point, start)
        let distFromEnd = distance(point, end)

        return abs(distFromStart + distFromEnd - segmentLength) < threshold
    }

    /// Remove duplicate corners that are very close to each other
    private func removeDuplicateCorners(_ corners: [DetectedCorner], threshold: Float) -> [DetectedCorner] {
        var unique: [DetectedCorner] = []

        for corner in corners {
            let isDuplicate = unique.contains { existing in
                distance(existing.position, corner.position) < threshold
            }

            if !isDuplicate {
                unique.append(corner)
            }
        }

        return unique
    }

    // MARK: - Queries

    /// Get all corners within a radius of a point
    func getCornersNear(position: SIMD3<Float>, radius: Float) -> [DetectedCorner] {
        return detectedCorners.filter { corner in
            distance(corner.position, position) <= radius
        }
    }

    /// Get the nearest corner to a position
    func getNearestCorner(to position: SIMD3<Float>) -> DetectedCorner? {
        return detectedCorners.min { corner1, corner2 in
            distance(corner1.position, position) < distance(corner2.position, position)
        }
    }

    /// Get all horizontal planes (floors, tables, etc.)
    func getHorizontalPlanes() -> [DetectedPlane] {
        return detectedPlanes.values.filter { $0.alignment == .horizontal }
    }

    /// Get all vertical planes (walls, doors, etc.)
    func getVerticalPlanes() -> [DetectedPlane] {
        return detectedPlanes.values.filter { $0.alignment == .vertical }
    }
}

// MARK: - Supporting Types

struct IntersectionLine {
    let point: SIMD3<Float>
    let direction: SIMD3<Float>
}

/// Represents a detected plane in the real world
class DetectedPlane: Identifiable {
    let id: UUID
    var transform: simd_float4x4
    var center: SIMD3<Float>
    var normal: SIMD3<Float>
    var alignment: PlaneAnchor.Alignment
    var classification: PlaneAnchor.Classification
    var geometry: PlaneGeometry?

    init(anchor: PlaneAnchor) {
        self.id = anchor.id
        self.transform = anchor.originFromAnchorTransform
        self.alignment = anchor.alignment
        self.classification = anchor.classification

        let transformColumn = anchor.originFromAnchorTransform.columns.3
        self.center = SIMD3<Float>(transformColumn.x, transformColumn.y, transformColumn.z)

        // Extract normal from transform (Y-axis for horizontal, Z-axis for vertical)
        if alignment == .horizontal {
            self.normal = SIMD3<Float>(
                anchor.originFromAnchorTransform.columns.1.x,
                anchor.originFromAnchorTransform.columns.1.y,
                anchor.originFromAnchorTransform.columns.1.z
            )
        } else {
            self.normal = SIMD3<Float>(
                anchor.originFromAnchorTransform.columns.2.x,
                anchor.originFromAnchorTransform.columns.2.y,
                anchor.originFromAnchorTransform.columns.2.z
            )
        }

        self.geometry = PlaneGeometry(from: anchor.geometry)
    }

    func update(from anchor: PlaneAnchor) {
        self.transform = anchor.originFromAnchorTransform
        self.alignment = anchor.alignment
        self.classification = anchor.classification

        let transformColumn = anchor.originFromAnchorTransform.columns.3
        self.center = SIMD3<Float>(transformColumn.x, transformColumn.y, transformColumn.z)

        if alignment == .horizontal {
            self.normal = SIMD3<Float>(
                anchor.originFromAnchorTransform.columns.1.x,
                anchor.originFromAnchorTransform.columns.1.y,
                anchor.originFromAnchorTransform.columns.1.z
            )
        } else {
            self.normal = SIMD3<Float>(
                anchor.originFromAnchorTransform.columns.2.x,
                anchor.originFromAnchorTransform.columns.2.y,
                anchor.originFromAnchorTransform.columns.2.z
            )
        }

        self.geometry = PlaneGeometry(from: anchor.geometry)
    }
}

struct PlaneGeometry {
    let boundaryVertices: [SIMD2<Float>]

    init?(from meshGeometry: MeshResource.Contents?) {
        guard let geometry = meshGeometry else {
            return nil
        }

        // Extract boundary vertices from mesh
        // This is a simplified version - actual implementation may need more processing
        var vertices: [SIMD2<Float>] = []

        // For plane anchors, we can access the boundary polygon
        // This is available through the PlaneAnchor's geometry
        // Note: This is a placeholder - actual visionOS API may differ

        self.boundaryVertices = vertices
    }

    init(from geometry: PlaneAnchor.Geometry) {
        // Extract boundary vertices from PlaneAnchor.Geometry
        self.boundaryVertices = geometry.meshVertices.asSIMD2Array()
    }
}

/// Represents a detected corner in the real world
struct DetectedCorner: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let type: CornerType
    let associatedPlanes: [UUID]
    let timestamp = Date()

    enum CornerType {
        case planeBoundary      // Corner from plane edge
        case planeIntersection  // Corner where planes meet
    }
}

// MARK: - Extensions

extension PlaneAnchor.Alignment {
    var description: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        @unknown default: return "Unknown"
        }
    }
}

extension PlaneAnchor.Classification {
    var description: String {
        switch self {
        case .wall: return "Wall"
        case .floor: return "Floor"
        case .ceiling: return "Ceiling"
        case .table: return "Table"
        case .seat: return "Seat"
        case .window: return "Window"
        case .door: return "Door"
        @unknown default: return "Unknown"
        }
    }
}

extension PlaneAnchor.Geometry {
    func meshVertices() -> [SIMD2<Float>] {
        // Convert MeshBuffer to array of vertices
        // This accesses the actual boundary vertices from the plane geometry
        var vertices: [SIMD2<Float>] = []

        // Access the mesh buffer data
        // Note: Actual implementation depends on visionOS API

        return vertices
    }
}

extension MeshBuffer {
    func asSIMD2Array() -> [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []

        // Convert buffer to SIMD2 array
        // This is a simplified placeholder

        return result
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let planeDetected = Notification.Name("planeDetected")
    static let cornersUpdated = Notification.Name("cornersUpdated")
}
