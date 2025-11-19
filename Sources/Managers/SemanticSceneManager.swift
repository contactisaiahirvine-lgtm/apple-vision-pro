import Foundation
import ARKit
import RealityKit
import simd

/// Manages semantic scene understanding using ARKit classifications
@MainActor
class SemanticSceneManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var detectedSurfaces: [SemanticSurface] = []

    // MARK: - Semantic Classification

    enum SurfaceType: String, CaseIterable {
        case floor
        case ceiling
        case wall
        case door
        case window
        case table
        case seat
        case bed

        var autoAlignment: Bool {
            switch self {
            case .floor, .table, .seat: return true
            case .wall, .door, .window: return false
            case .ceiling, .bed: return false
            }
        }
    }

    struct SemanticSurface: Identifiable {
        let id: UUID
        let type: SurfaceType
        let anchor: ARPlaneAnchor
        let center: SIMD3<Float>
        let normal: SIMD3<Float>
        let extent: SIMD3<Float>
        let classification: ARPlaneAnchor.Classification
    }

    // MARK: - Surface Tracking

    private var trackedSurfaces: [UUID: SemanticSurface] = [:]

    // MARK: - AR Integration

    private weak var arView: ARView?

    // MARK: - Auto-Alignment Rules

    private var autoAlignmentEnabled = true
    private var alignmentRules: [SurfaceType: AlignmentRule] = [:]

    struct AlignmentRule {
        let snapToSurface: Bool
        let normalAlignment: Bool
        let centerAlignment: Bool
    }

    // MARK: - Statistics

    private(set) var surfacesDetected: Int = 0
    private(set) var autoAlignments: Int = 0

    // MARK: - Initialization

    init() {
        setupDefaultRules()
        print("✅ Semantic Scene Manager initialized")
    }

    private func setupDefaultRules() {
        alignmentRules[.floor] = AlignmentRule(snapToSurface: true, normalAlignment: true, centerAlignment: false)
        alignmentRules[.table] = AlignmentRule(snapToSurface: true, normalAlignment: true, centerAlignment: true)
        alignmentRules[.seat] = AlignmentRule(snapToSurface: true, normalAlignment: false, centerAlignment: true)
        alignmentRules[.wall] = AlignmentRule(snapToSurface: false, normalAlignment: true, centerAlignment: false)
    }

    // MARK: - Setup

    func setup(arView: ARView) {
        self.arView = arView

        // Enable plane detection with classification
        if let config = arView.session.configuration as? ARWorldTrackingConfiguration {
            config.planeDetection = [.horizontal, .vertical]
            arView.session.run(config)
        }

        print("Semantic scene understanding linked to ARView")
    }

    // MARK: - Surface Detection

    /// Process plane anchor for semantic classification
    func processPlaneAnchor(_ planeAnchor: ARPlaneAnchor) {
        guard isEnabled else { return }

        let surfaceType = classifyPlane(planeAnchor)

        let transform = Transform(matrix: planeAnchor.transform)
        let normal = SIMD3<Float>(0, 1, 0)  // Would extract from plane

        let surface = SemanticSurface(
            id: planeAnchor.identifier,
            type: surfaceType,
            anchor: planeAnchor,
            center: transform.translation,
            normal: normal,
            extent: SIMD3<Float>(planeAnchor.planeExtent.width, 0, planeAnchor.planeExtent.height),
            classification: planeAnchor.classification
        )

        trackedSurfaces[planeAnchor.identifier] = surface

        if !detectedSurfaces.contains(where: { $0.id == surface.id }) {
            detectedSurfaces.append(surface)
            surfacesDetected += 1
        }

        NotificationCenter.default.post(
            name: .semanticSurfaceDetected,
            object: surface
        )
    }

    private func classifyPlane(_ plane: ARPlaneAnchor) -> SurfaceType {
        switch plane.classification {
        case .floor:
            return .floor
        case .ceiling:
            return .ceiling
        case .wall:
            return .wall
        case .door:
            return .door
        case .window:
            return .window
        case .table:
            return .table
        case .seat:
            return .seat
        default:
            // Use alignment as fallback
            return plane.alignment == .horizontal ? .floor : .wall
        }
    }

    // MARK: - Auto-Alignment

    /// Automatically align entity to detected surface
    func autoAlign(
        entity: Entity,
        preferredSurfaces: [SurfaceType] = [.floor, .table]
    ) -> Bool {
        guard autoAlignmentEnabled else { return false }

        // Find closest matching surface
        guard let surface = findClosestSurface(
            to: entity.position,
            types: preferredSurfaces
        ) else {
            return false
        }

        // Apply alignment rule
        if let rule = alignmentRules[surface.type] {
            applyAlignment(to: entity, surface: surface, rule: rule)
            autoAlignments += 1
            return true
        }

        return false
    }

    private func findClosestSurface(
        to position: SIMD3<Float>,
        types: [SurfaceType]
    ) -> SemanticSurface? {
        let matchingSurfaces = detectedSurfaces.filter { types.contains($0.type) }

        return matchingSurfaces.min { surface1, surface2 in
            simd_distance(surface1.center, position) < simd_distance(surface2.center, position)
        }
    }

    private func applyAlignment(to entity: Entity, surface: SemanticSurface, rule: AlignmentRule) {
        if rule.snapToSurface {
            entity.position.y = surface.center.y
        }

        if rule.normalAlignment {
            // Align to surface normal
            let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: surface.normal)
            entity.orientation = rotation
        }

        if rule.centerAlignment {
            entity.position.x = surface.center.x
            entity.position.z = surface.center.z
        }

        print("Auto-aligned entity to \(surface.type.rawValue)")
    }

    // MARK: - Query Methods

    /// Get all surfaces of specific type
    func getSurfaces(ofType type: SurfaceType) -> [SemanticSurface] {
        return detectedSurfaces.filter { $0.type == type }
    }

    /// Find floor surface closest to position
    func findNearestFloor(to position: SIMD3<Float>) -> SemanticSurface? {
        return findClosestSurface(to: position, types: [.floor])
    }

    /// Find table surfaces
    func findTables() -> [SemanticSurface] {
        return getSurfaces(ofType: .table)
    }

    /// Check if position is on floor
    func isOnFloor(position: SIMD3<Float>, tolerance: Float = 0.1) -> Bool {
        guard let floor = findNearestFloor(to: position) else { return false }
        return abs(position.y - floor.center.y) < tolerance
    }

    // MARK: - Configuration

    func setAutoAlignment(_ enabled: Bool) {
        autoAlignmentEnabled = enabled
        print("Auto-alignment: \(enabled)")
    }

    func setAlignmentRule(for surface: SurfaceType, rule: AlignmentRule) {
        alignmentRules[surface] = rule
        print("Set alignment rule for \(surface.rawValue)")
    }

    // MARK: - Statistics

    func getSemanticStats() -> SemanticStats {
        var typeCounts: [SurfaceType: Int] = [:]
        for type in SurfaceType.allCases {
            typeCounts[type] = getSurfaces(ofType: type).count
        }

        return SemanticStats(
            isEnabled: isEnabled,
            totalSurfaces: detectedSurfaces.count,
            surfacesDetected: surfacesDetected,
            autoAlignments: autoAlignments,
            surfaceTypeCounts: typeCounts,
            autoAlignmentEnabled: autoAlignmentEnabled
        )
    }

    func getDebugInfo() -> String {
        let stats = getSemanticStats()

        var info = "=== Semantic Scene ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Total Surfaces: \(stats.totalSurfaces)\n"
        info += "Auto-Alignments: \(stats.autoAlignments)\n"
        info += "\nSurface Types:\n"

        for type in SurfaceType.allCases {
            let count = stats.surfaceTypeCounts[type] ?? 0
            if count > 0 {
                info += "  \(type.rawValue.capitalized): \(count)\n"
            }
        }

        info += "==================="

        return info
    }
}

struct SemanticStats {
    let isEnabled: Bool
    let totalSurfaces: Int
    let surfacesDetected: Int
    let autoAlignments: Int
    let surfaceTypeCounts: [SemanticSceneManager.SurfaceType: Int]
    let autoAlignmentEnabled: Bool
}

extension Notification.Name {
    static let semanticSurfaceDetected = Notification.Name("semanticSurfaceDetected")
}
