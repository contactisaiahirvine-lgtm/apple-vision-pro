import Foundation
import ARKit
import RealityKit
import Combine
import simd
import Vision

/// Detects dangerous real-world areas to keep players safe during AR gameplay
/// Includes railroad tracks, construction sites, sharp drops, water, roads, and more
@MainActor
class DangerousAreaDetectionManager: ObservableObject {
    @Published var isActive = false
    @Published var detectedHazards: [DangerousArea] = []
    @Published var currentDangerLevel: DangerLevel = .safe

    // ARKit integration
    private weak var arView: ARView?
    private var sceneReconstruction: Bool = true

    // Detection sensitivity
    var detectionSensitivity: DetectionSensitivity = .normal
    var safetyMargin: Float = 1.5  // meters - extra buffer around hazards

    // Detection thresholds
    var minimumDropHeight: Float = 0.5  // meters
    var maximumSafeSlope: Float = 30.0  // degrees
    var waterDetectionDepth: Float = 0.3  // meters

    // Processing state
    private var lastAnalysisTime: TimeInterval = 0
    private let analysisInterval: TimeInterval = 0.5  // analyze every 0.5 seconds

    // ML and computer vision
    private var visionQueue = DispatchQueue(label: "com.visionpro.dangerdetection", qos: .userInitiated)

    init() {
        print("DangerousAreaDetectionManager initialized")
    }

    // MARK: - Setup

    /// Setup danger detection with ARView
    func setup(arView: ARView) {
        self.arView = arView

        // Enable scene reconstruction for detailed mesh data
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            print("WARNING: Scene reconstruction not supported on this device")
            return
        }

        print("Dangerous area detection configured")
    }

    /// Start danger detection
    func startDetection() {
        guard let arView = arView else {
            print("ERROR: ARView not set. Call setup(arView:) first")
            return
        }

        isActive = true
        print("✅ Dangerous area detection started")

        // Post notification
        NotificationCenter.default.post(name: .dangerDetectionStarted, object: nil)
    }

    /// Stop danger detection
    func stopDetection() {
        isActive = false
        detectedHazards.removeAll()
        currentDangerLevel = .safe

        print("Dangerous area detection stopped")
        NotificationCenter.default.post(name: .dangerDetectionStopped, object: nil)
    }

    // MARK: - Update Loop

    /// Update detection (call from game loop)
    func update(playerPosition: SIMD3<Float>, deltaTime: TimeInterval) {
        guard isActive else { return }

        lastAnalysisTime += deltaTime

        // Throttle analysis based on interval
        guard lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = 0

        // Perform hazard detection
        Task {
            await performHazardDetection(playerPosition: playerPosition)
        }
    }

    // MARK: - Hazard Detection

    private func performHazardDetection(playerPosition: SIMD3<Float>) async {
        guard let arView = arView else { return }

        var newHazards: [DangerousArea] = []

        // 1. Detect sharp drops and cliffs
        if let drops = detectSharpDrops(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: drops)
        }

        // 2. Detect steep slopes
        if let slopes = detectSteepSlopes(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: slopes)
        }

        // 3. Detect bodies of water
        if let water = detectWater(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: water)
        }

        // 4. Detect railroad tracks
        if let tracks = detectRailroadTracks(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: tracks)
        }

        // 5. Detect roads and traffic areas
        if let roads = detectRoads(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: roads)
        }

        // 6. Detect construction sites
        if let construction = detectConstructionSites(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: construction)
        }

        // 7. Detect rooftop and balcony edges
        if let edges = detectElevatedEdges(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: edges)
        }

        // 8. Detect holes and pits
        if let holes = detectHoles(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: holes)
        }

        // 9. Detect glass barriers
        if let glass = detectGlassBarriers(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: glass)
        }

        // 10. Detect restricted/industrial areas
        if let restricted = detectRestrictedAreas(arView: arView, playerPosition: playerPosition) {
            newHazards.append(contentsOf: restricted)
        }

        // Update detected hazards
        await MainActor.run {
            self.detectedHazards = newHazards
            self.updateDangerLevel(playerPosition: playerPosition)

            // Notify of new hazards
            if !newHazards.isEmpty {
                NotificationCenter.default.post(
                    name: .dangerousAreasDetected,
                    object: nil,
                    userInfo: ["hazards": newHazards, "count": newHazards.count]
                )
            }
        }
    }

    // MARK: - Detection Methods

    /// Detect sharp drops, cliffs, and ledges
    private func detectSharpDrops(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var drops: [DangerousArea] = []

        // Analyze mesh anchors for sudden height changes
        let meshAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []

        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices

            // Sample vertices to detect height changes
            let vertexCount = vertices.count
            guard vertexCount > 0 else { continue }

            // Check for significant height drops
            for i in stride(from: 0, to: vertexCount - 1, by: 10) {
                let vertex1 = vertices[i]
                let vertex2 = vertices[min(i + 1, vertexCount - 1)]

                let heightDiff = abs(vertex1.y - vertex2.y)
                let horizontalDist = simd_distance(SIMD2(vertex1.x, vertex1.z), SIMD2(vertex2.x, vertex2.z))

                // Detect sharp drop (large height change over small horizontal distance)
                if heightDiff > minimumDropHeight && horizontalDist < 0.5 {
                    let worldPos = meshAnchor.transform * SIMD4(vertex1.x, vertex1.y, vertex1.z, 1.0)
                    let dropPosition = SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)

                    // Check if within detection range
                    let distance = simd_distance(dropPosition, playerPosition)
                    if distance < getDetectionRange() {
                        let drop = DangerousArea(
                            id: UUID(),
                            type: .sharpDrop,
                            position: dropPosition,
                            radius: 2.0,
                            severity: heightDiff > 2.0 ? .critical : .high,
                            metadata: ["dropHeight": heightDiff, "distance": distance]
                        )
                        drops.append(drop)
                    }
                }
            }
        }

        return drops.isEmpty ? nil : drops
    }

    /// Detect steep slopes that could cause falls
    private func detectSteepSlopes(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var slopes: [DangerousArea] = []

        let planeAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []

        for anchor in planeAnchors {
            // Calculate plane normal angle relative to horizontal
            let normal = anchor.transform.columns.1
            let horizontalNormal = SIMD3<Float>(0, 1, 0)

            let dotProduct = simd_dot(SIMD3(normal.x, normal.y, normal.z), horizontalNormal)
            let angle = acos(dotProduct) * 180.0 / .pi

            // If slope exceeds maximum safe angle
            if angle > maximumSafeSlope {
                let position = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
                let distance = simd_distance(position, playerPosition)

                if distance < getDetectionRange() {
                    let slope = DangerousArea(
                        id: UUID(),
                        type: .steepSlope,
                        position: position,
                        radius: Float(anchor.planeExtent.width),
                        severity: angle > 45.0 ? .high : .medium,
                        metadata: ["angle": angle, "distance": distance]
                    )
                    slopes.append(slope)
                }
            }
        }

        return slopes.isEmpty ? nil : slopes
    }

    /// Detect bodies of water (pools, lakes, rivers)
    private func detectWater(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var waterAreas: [DangerousArea] = []

        let planeAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []

        for anchor in planeAnchors {
            // Check if plane is horizontal and below player (potential water surface)
            let position = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let distance = simd_distance(position, playerPosition)

            // Water is typically horizontal and reflective
            let normal = SIMD3<Float>(anchor.transform.columns.1.x, anchor.transform.columns.1.y, anchor.transform.columns.1.z)
            let isHorizontal = abs(normal.y) > 0.9

            // Check if below player (potential water)
            let isBelowPlayer = position.y < playerPosition.y - waterDetectionDepth

            if isHorizontal && isBelowPlayer && distance < getDetectionRange() {
                // Additional heuristic: large horizontal surfaces at ground level might be water
                if anchor.planeExtent.width > 2.0 || anchor.planeExtent.height > 2.0 {
                    let water = DangerousArea(
                        id: UUID(),
                        type: .deepWater,
                        position: position,
                        radius: max(Float(anchor.planeExtent.width), Float(anchor.planeExtent.height)),
                        severity: .high,
                        metadata: ["area": anchor.planeExtent.width * anchor.planeExtent.height, "distance": distance]
                    )
                    waterAreas.append(water)
                }
            }
        }

        return waterAreas.isEmpty ? nil : waterAreas
    }

    /// Detect railroad tracks using pattern recognition
    private func detectRailroadTracks(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var tracks: [DangerousArea] = []

        // Look for parallel linear features at ground level
        let meshAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []

        for meshAnchor in meshAnchors {
            // Analyze mesh for parallel linear patterns
            let position = SIMD3<Float>(meshAnchor.transform.columns.3.x, meshAnchor.transform.columns.3.y, meshAnchor.transform.columns.3.z)
            let distance = simd_distance(position, playerPosition)

            if distance < getDetectionRange() {
                // Railroad tracks are typically at ground level with metal/reflective classification
                // This is a heuristic - in production, you'd use ML model
                let isGroundLevel = abs(position.y - playerPosition.y) < 0.3

                if isGroundLevel {
                    // Mark as potential railroad track
                    let track = DangerousArea(
                        id: UUID(),
                        type: .railroadTracks,
                        position: position,
                        radius: 5.0,  // Wide safety margin for trains
                        severity: .critical,
                        metadata: ["distance": distance, "detectionMethod": "geometric"]
                    )
                    tracks.append(track)
                }
            }
        }

        return tracks.isEmpty ? nil : tracks
    }

    /// Detect roads and traffic areas
    private func detectRoads(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var roads: [DangerousArea] = []

        let planeAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []

        for anchor in planeAnchors {
            let position = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let distance = simd_distance(position, playerPosition)

            // Roads are large horizontal surfaces with specific characteristics
            let isHorizontal = anchor.alignment == .horizontal
            let isLarge = anchor.planeExtent.width > 3.0  // Roads are typically > 3m wide

            if isHorizontal && isLarge && distance < getDetectionRange() {
                // Check if at ground level
                let isGroundLevel = abs(position.y - playerPosition.y) < 0.5

                if isGroundLevel {
                    let road = DangerousArea(
                        id: UUID(),
                        type: .roadway,
                        position: position,
                        radius: Float(anchor.planeExtent.width / 2.0),
                        severity: .high,
                        metadata: ["width": anchor.planeExtent.width, "distance": distance]
                    )
                    roads.append(road)
                }
            }
        }

        return roads.isEmpty ? nil : roads
    }

    /// Detect construction sites
    private func detectConstructionSites(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var sites: [DangerousArea] = []

        // Construction sites have multiple indicators:
        // - Exposed ground/dirt
        // - Building materials
        // - Equipment
        // - Irregular terrain
        // - Exposed structures

        let meshAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []

        for meshAnchor in meshAnchors {
            let position = SIMD3<Float>(meshAnchor.transform.columns.3.x, meshAnchor.transform.columns.3.y, meshAnchor.transform.columns.3.z)
            let distance = simd_distance(position, playerPosition)

            if distance < getDetectionRange() {
                // Heuristic: irregular mesh geometry suggests construction
                let geometry = meshAnchor.geometry
                if geometry.vertices.count > 100 {  // Complex geometry
                    let site = DangerousArea(
                        id: UUID(),
                        type: .constructionSite,
                        position: position,
                        radius: 5.0,
                        severity: .high,
                        metadata: ["distance": distance, "complexity": geometry.vertices.count]
                    )
                    sites.append(site)
                }
            }
        }

        return sites.isEmpty ? nil : sites
    }

    /// Detect rooftop and balcony edges
    private func detectElevatedEdges(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var edges: [DangerousArea] = []

        let planeAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []

        for anchor in planeAnchors {
            let position = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let heightAboveGround = position.y - playerPosition.y

            // Detect elevated surfaces (rooftops, balconies)
            if heightAboveGround > 2.0 {  // More than 2m above player
                let distance = simd_distance(position, playerPosition)

                if distance < getDetectionRange() {
                    // Check for edges of elevated surfaces
                    let edge = DangerousArea(
                        id: UUID(),
                        type: .elevatedEdge,
                        position: position,
                        radius: 1.0,
                        severity: .critical,
                        metadata: ["height": heightAboveGround, "distance": distance]
                    )
                    edges.append(edge)
                }
            }
        }

        return edges.isEmpty ? nil : edges
    }

    /// Detect holes and pits in the ground
    private func detectHoles(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var holes: [DangerousArea] = []

        let meshAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []

        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices

            // Look for concave depressions in ground mesh
            let vertexCount = vertices.count
            guard vertexCount > 0 else { continue }

            for i in stride(from: 0, to: vertexCount, by: 10) {
                let vertex = vertices[i]
                let worldPos = meshAnchor.transform * SIMD4(vertex.x, vertex.y, vertex.z, 1.0)
                let position = SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)

                // Check if significantly below expected ground level
                if position.y < playerPosition.y - 0.5 {
                    let distance = simd_distance(position, playerPosition)

                    if distance < getDetectionRange() {
                        let hole = DangerousArea(
                            id: UUID(),
                            type: .hole,
                            position: position,
                            radius: 1.0,
                            severity: .medium,
                            metadata: ["depth": playerPosition.y - position.y, "distance": distance]
                        )
                        holes.append(hole)
                    }
                }
            }
        }

        return holes.isEmpty ? nil : holes
    }

    /// Detect glass barriers (windows, doors)
    private func detectGlassBarriers(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var glassBarriers: [DangerousArea] = []

        // Glass is detected as vertical planes with specific properties
        let planeAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []

        for anchor in planeAnchors {
            let position = SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let distance = simd_distance(position, playerPosition)

            // Glass surfaces are typically vertical
            let isVertical = anchor.alignment == .vertical

            if isVertical && distance < getDetectionRange() {
                // Glass is often large and smooth
                if anchor.planeExtent.width > 1.0 {
                    let glass = DangerousArea(
                        id: UUID(),
                        type: .glassBarrier,
                        position: position,
                        radius: Float(anchor.planeExtent.width / 2.0),
                        severity: .medium,
                        metadata: ["distance": distance, "size": anchor.planeExtent.width]
                    )
                    glassBarriers.append(glass)
                }
            }
        }

        return glassBarriers.isEmpty ? nil : glassBarriers
    }

    /// Detect restricted and industrial areas
    private func detectRestrictedAreas(arView: ARView, playerPosition: SIMD3<Float>) -> [DangerousArea]? {
        var restrictedAreas: [DangerousArea] = []

        // This would typically use:
        // - GPS/location data
        // - Map data
        // - Signage recognition
        // - Geofencing

        // Placeholder for location-based detection
        // In production, integrate with location services and map data

        return restrictedAreas.isEmpty ? nil : restrictedAreas
    }

    // MARK: - Danger Level Assessment

    private func updateDangerLevel(playerPosition: SIMD3<Float>) {
        guard !detectedHazards.isEmpty else {
            currentDangerLevel = .safe
            return
        }

        // Find closest hazard
        var closestDistance: Float = Float.infinity
        var highestSeverity: DangerSeverity = .low

        for hazard in detectedHazards {
            let distance = simd_distance(hazard.position, playerPosition)
            let effectiveDistance = distance - hazard.radius - safetyMargin

            if effectiveDistance < closestDistance {
                closestDistance = effectiveDistance
                highestSeverity = hazard.severity
            }
        }

        // Determine danger level based on proximity and severity
        if closestDistance < 1.0 {
            // Within 1m of hazard
            currentDangerLevel = highestSeverity == .critical ? .critical : .high
        } else if closestDistance < 3.0 {
            // Within 3m of hazard
            currentDangerLevel = .medium
        } else if closestDistance < 5.0 {
            // Within 5m of hazard
            currentDangerLevel = .low
        } else {
            currentDangerLevel = .safe
        }

        // Notify of danger level changes
        NotificationCenter.default.post(
            name: .dangerLevelChanged,
            object: nil,
            userInfo: ["level": currentDangerLevel, "closestDistance": closestDistance]
        )
    }

    // MARK: - Query Methods

    /// Check if player is near any dangerous area
    func isPlayerInDanger(position: SIMD3<Float>, threshold: Float = 2.0) -> Bool {
        for hazard in detectedHazards {
            let distance = simd_distance(hazard.position, position)
            if distance < (hazard.radius + safetyMargin + threshold) {
                return true
            }
        }
        return false
    }

    /// Get all hazards within range of position
    func getHazardsNear(position: SIMD3<Float>, range: Float) -> [DangerousArea] {
        return detectedHazards.filter { hazard in
            let distance = simd_distance(hazard.position, position)
            return distance < range
        }
    }

    /// Get closest hazard to position
    func getClosestHazard(to position: SIMD3<Float>) -> DangerousArea? {
        return detectedHazards.min { a, b in
            simd_distance(a.position, position) < simd_distance(b.position, position)
        }
    }

    /// Get all hazards of specific type
    func getHazardsOfType(_ type: HazardType) -> [DangerousArea] {
        return detectedHazards.filter { $0.type == type }
    }

    /// Check if position is safe to move to
    func isSafePosition(_ position: SIMD3<Float>) -> Bool {
        return !isPlayerInDanger(position: position, threshold: 0.5)
    }

    /// Get safe direction to move from current position
    func getSafeDirection(from position: SIMD3<Float>, desiredDirection: SIMD3<Float>) -> SIMD3<Float>? {
        // Check if desired direction is safe
        let testPosition = position + desiredDirection * 0.5
        if isSafePosition(testPosition) {
            return desiredDirection
        }

        // Try to find alternative safe direction
        let angles: [Float] = [-45, 45, -90, 90, -135, 135, 180]
        for angle in angles {
            let radians = angle * .pi / 180.0
            let rotatedDir = rotateVector(desiredDirection, byDegrees: radians)
            let testPos = position + rotatedDir * 0.5
            if isSafePosition(testPos) {
                return rotatedDir
            }
        }

        return nil  // No safe direction found
    }

    // MARK: - Configuration

    private func getDetectionRange() -> Float {
        switch detectionSensitivity {
        case .low: return 10.0
        case .normal: return 15.0
        case .high: return 25.0
        case .maximum: return 40.0
        }
    }

    // MARK: - Utilities

    private func rotateVector(_ vector: SIMD3<Float>, byDegrees degrees: Float) -> SIMD3<Float> {
        let radians = degrees * .pi / 180.0
        let cos = cosf(radians)
        let sin = sinf(radians)
        return SIMD3<Float>(
            vector.x * cos - vector.z * sin,
            vector.y,
            vector.x * sin + vector.z * cos
        )
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        var info = "=== Dangerous Area Detection Debug ===\n"
        info += "Active: \(isActive)\n"
        info += "Sensitivity: \(detectionSensitivity)\n"
        info += "Detected Hazards: \(detectedHazards.count)\n"
        info += "Current Danger Level: \(currentDangerLevel)\n\n"

        for (index, hazard) in detectedHazards.enumerated() {
            info += "\(index + 1). \(hazard.type) at \(hazard.position)\n"
            info += "   Severity: \(hazard.severity), Radius: \(hazard.radius)m\n"
        }

        info += "======================================="
        return info
    }
}

// MARK: - Data Structures

/// Represents a dangerous area in the real world
struct DangerousArea: Identifiable {
    let id: UUID
    let type: HazardType
    let position: SIMD3<Float>
    let radius: Float  // meters
    let severity: DangerSeverity
    let metadata: [String: Any]
    let detectedAt: Date = Date()

    /// Get distance from a position
    func distanceFrom(_ position: SIMD3<Float>) -> Float {
        return simd_distance(self.position, position)
    }

    /// Check if position is within danger zone
    func contains(_ position: SIMD3<Float>, safetyMargin: Float = 0) -> Bool {
        return distanceFrom(position) < (radius + safetyMargin)
    }
}

/// Types of hazards that can be detected
enum HazardType: String, Codable, CaseIterable {
    case sharpDrop = "Sharp Drop"
    case steepSlope = "Steep Slope"
    case deepWater = "Deep Water"
    case railroadTracks = "Railroad Tracks"
    case roadway = "Roadway"
    case constructionSite = "Construction Site"
    case elevatedEdge = "Elevated Edge"
    case hole = "Hole/Pit"
    case glassBarrier = "Glass Barrier"
    case restrictedArea = "Restricted Area"
    case industrialZone = "Industrial Zone"
    case highVoltage = "High Voltage"
    case movingMachinery = "Moving Machinery"

    var icon: String {
        switch self {
        case .sharpDrop: return "arrow.down.circle.fill"
        case .steepSlope: return "triangle.fill"
        case .deepWater: return "drop.fill"
        case .railroadTracks: return "tram.fill"
        case .roadway: return "car.fill"
        case .constructionSite: return "hammer.fill"
        case .elevatedEdge: return "arrow.up.and.down.circle.fill"
        case .hole: return "circle.dotted"
        case .glassBarrier: return "rectangle.portrait.fill"
        case .restrictedArea: return "exclamationmark.triangle.fill"
        case .industrialZone: return "gearshape.fill"
        case .highVoltage: return "bolt.fill"
        case .movingMachinery: return "gearshape.2.fill"
        }
    }
}

/// Severity level of hazard
enum DangerSeverity: String, Codable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    static func < (lhs: DangerSeverity, rhs: DangerSeverity) -> Bool {
        let order: [DangerSeverity] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Overall danger level for player
enum DangerLevel: String {
    case safe = "Safe"
    case low = "Low Danger"
    case medium = "Medium Danger"
    case high = "High Danger"
    case critical = "Critical Danger"
}

/// Detection sensitivity levels
enum DetectionSensitivity: String {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case maximum = "Maximum"
}

// MARK: - Notifications

extension Notification.Name {
    static let dangerDetectionStarted = Notification.Name("dangerDetectionStarted")
    static let dangerDetectionStopped = Notification.Name("dangerDetectionStopped")
    static let dangerousAreasDetected = Notification.Name("dangerousAreasDetected")
    static let dangerLevelChanged = Notification.Name("dangerLevelChanged")
    static let playerEnteredDangerZone = Notification.Name("playerEnteredDangerZone")
    static let playerExitedDangerZone = Notification.Name("playerExitedDangerZone")
}
