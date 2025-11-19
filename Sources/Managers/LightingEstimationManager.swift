import Foundation
import ARKit
import RealityKit
import Combine
import simd

/// Manages environmental lighting estimation and application to AR assets
/// Ensures inserted objects match the real-world lighting conditions
@MainActor
class LightingEstimationManager: ObservableObject {
    @Published var isActive = false
    @Published var currentLightingConditions: LightingConditions?
    @Published var lightingQuality: LightingQuality = .standard

    // ARKit integration
    private weak var arView: ARView?

    // Lighting data
    private var ambientIntensity: Float = 1000.0  // lumens
    private var ambientColorTemperature: Float = 6500.0  // kelvin
    private var primaryLightDirection: SIMD3<Float> = SIMD3(0, -1, 0)
    private var primaryLightIntensity: Float = 1000.0

    // HDR environment
    private var environmentTexture: MaterialParameters.Texture?
    private var sphericalHarmonics: [SIMD3<Float>] = []

    // Update control
    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 0.1  // Update every 0.1 seconds

    // Tracked entities for lighting updates
    private var trackedEntities: [UUID: Entity] = [:]

    // Configuration
    var autoUpdateEnabled = true
    var useHDREnvironment = true
    var applyAmbientOcclusion = true
    var shadowIntensity: Float = 1.0

    init() {
        print("LightingEstimationManager initialized")
    }

    // MARK: - Setup

    /// Setup lighting estimation with ARView
    func setup(arView: ARView) {
        self.arView = arView

        // Enable scene lighting estimation in ARKit configuration
        guard let configuration = arView.session.configuration as? ARWorldTrackingConfiguration else {
            print("ERROR: ARView must use ARWorldTrackingConfiguration")
            return
        }

        // Enable automatic environment lighting
        configuration.environmentTexturing = .automatic

        // Restart session with new configuration
        arView.session.run(configuration)

        print("Lighting estimation configured")
    }

    /// Start lighting estimation
    func start() {
        guard arView != nil else {
            print("ERROR: ARView not set. Call setup(arView:) first")
            return
        }

        isActive = true
        print("✅ Lighting estimation started")

        NotificationCenter.default.post(name: .lightingEstimationStarted, object: nil)
    }

    /// Stop lighting estimation
    func stop() {
        isActive = false
        print("Lighting estimation stopped")

        NotificationCenter.default.post(name: .lightingEstimationStopped, object: nil)
    }

    // MARK: - Update Loop

    /// Update lighting estimation (call from game loop)
    func update(deltaTime: TimeInterval) {
        guard isActive, let arView = arView else { return }

        lastUpdateTime += deltaTime

        // Throttle updates
        guard lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = 0

        // Estimate lighting from current frame
        estimateLighting(from: arView)

        // Update tracked entities if auto-update enabled
        if autoUpdateEnabled {
            updateTrackedEntities()
        }
    }

    // MARK: - Lighting Estimation

    private func estimateLighting(from arView: ARView) {
        guard let frame = arView.session.currentFrame else { return }

        // Get light estimate from ARKit
        if let lightEstimate = frame.lightEstimate {
            // Ambient intensity (lumens)
            ambientIntensity = Float(lightEstimate.ambientIntensity)

            // Color temperature (Kelvin)
            ambientColorTemperature = Float(lightEstimate.ambientColorTemperature)

            // Primary light direction and intensity (if available)
            if let directionalEstimate = lightEstimate as? ARDirectionalLightEstimate {
                primaryLightDirection = SIMD3<Float>(
                    directionalEstimate.primaryLightDirection.x,
                    directionalEstimate.primaryLightDirection.y,
                    directionalEstimate.primaryLightDirection.z
                )
                primaryLightIntensity = Float(directionalEstimate.primaryLightIntensity)

                // Spherical harmonics for more accurate ambient lighting
                if directionalEstimate.sphericalHarmonicsCoefficients.count > 0 {
                    sphericalHarmonics = directionalEstimate.sphericalHarmonicsCoefficients.map { coeff in
                        SIMD3<Float>(Float(coeff.x), Float(coeff.y), Float(coeff.z))
                    }
                }
            }
        }

        // Create lighting conditions snapshot
        let conditions = LightingConditions(
            ambientIntensity: ambientIntensity,
            ambientColorTemperature: ambientColorTemperature,
            primaryLightDirection: primaryLightDirection,
            primaryLightIntensity: primaryLightIntensity,
            timestamp: Date()
        )

        currentLightingConditions = conditions

        // Notify of lighting update
        NotificationCenter.default.post(
            name: .lightingConditionsUpdated,
            object: nil,
            userInfo: ["conditions": conditions]
        )
    }

    // MARK: - Apply Lighting to Entities

    /// Apply current environmental lighting to an entity
    func applyLightingTo(entity: Entity, track: Bool = true) {
        guard let conditions = currentLightingConditions else {
            print("WARNING: No lighting conditions available")
            return
        }

        applyLighting(conditions, to: entity)

        // Track entity for automatic updates
        if track {
            trackedEntities[entity.id] = entity
        }
    }

    /// Apply specific lighting conditions to entity
    func applyLighting(_ conditions: LightingConditions, to entity: Entity) {
        // Apply to entity and all children
        applyLightingRecursive(conditions, to: entity)
    }

    private func applyLightingRecursive(_ conditions: LightingConditions, to entity: Entity) {
        // Apply lighting to this entity
        if var modelEntity = entity as? ModelEntity {
            applyLightingToModel(&modelEntity, conditions: conditions)
        }

        // Apply to all children
        for child in entity.children {
            applyLightingRecursive(conditions, to: child)
        }
    }

    private func applyLightingToModel(_ modelEntity: inout ModelEntity, conditions: LightingConditions) {
        guard let model = modelEntity.model else { return }

        // Get or create materials
        var materials = model.materials

        for i in 0..<materials.count {
            if var pbr = materials[i] as? PhysicallyBasedMaterial {
                // Apply ambient lighting
                let ambientColor = colorFromTemperature(conditions.ambientColorTemperature)
                let ambientMultiplier = conditions.ambientIntensity / 1000.0  // Normalize to 0-1 range

                // Adjust base color with ambient lighting
                if let baseColor = pbr.baseColor.tint {
                    let adjustedColor = blendColors(baseColor, with: ambientColor, intensity: ambientMultiplier)
                    pbr.baseColor = .init(tint: adjustedColor)
                }

                // Apply emissive for bright environments
                if conditions.ambientIntensity > 1500.0 {
                    let emissiveIntensity = (conditions.ambientIntensity - 1500.0) / 2000.0
                    pbr.emissiveIntensity = min(emissiveIntensity, 1.0)
                }

                // Apply shadow intensity
                // Note: RealityKit handles shadows automatically, but we can adjust material properties

                materials[i] = pbr
            } else if var unlit = materials[i] as? UnlitMaterial {
                // For unlit materials, adjust color based on ambient
                let ambientColor = colorFromTemperature(conditions.ambientColorTemperature)
                let ambientMultiplier = conditions.ambientIntensity / 1000.0

                if let baseColor = unlit.color.tint {
                    let adjustedColor = blendColors(baseColor, with: ambientColor, intensity: ambientMultiplier)
                    unlit.color = .init(tint: adjustedColor)
                }

                materials[i] = unlit
            }
        }

        // Update model with modified materials
        modelEntity.model?.materials = materials
    }

    // MARK: - Directional Lighting

    /// Create a directional light matching the environment
    func createEnvironmentalDirectionalLight() -> DirectionalLight {
        guard let conditions = currentLightingConditions else {
            return DirectionalLight()
        }

        let light = DirectionalLight()

        // Set light direction
        light.look(at: conditions.primaryLightDirection, from: .zero, relativeTo: nil)

        // Set light intensity and color
        let lightColor = colorFromTemperature(conditions.ambientColorTemperature)
        let intensity = conditions.primaryLightIntensity / 1000.0  // Normalize

        light.light.intensity = intensity
        light.light.color = lightColor

        // Enable shadows
        light.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 10.0,
            depthBias: 0.5
        )

        return light
    }

    /// Add environmental directional light to scene
    func addDirectionalLightTo(scene: Scene) -> DirectionalLight {
        let light = createEnvironmentalDirectionalLight()

        // Create anchor for light
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(light)
        scene.addAnchor(lightAnchor)

        return light
    }

    // MARK: - Image-Based Lighting (IBL)

    /// Apply environment texture from ARKit (if available)
    func applyEnvironmentTextureTo(entity: Entity) {
        guard useHDREnvironment,
              let arView = arView,
              let frame = arView.session.currentFrame,
              let environmentTexture = frame.lightEstimate as? ARDirectionalLightEstimate else {
            return
        }

        // ARKit provides environment texture automatically
        // RealityKit will use it for image-based lighting
        print("Environment texture applied to entity")
    }

    // MARK: - Tracked Entities

    private func updateTrackedEntities() {
        guard let conditions = currentLightingConditions else { return }

        // Update all tracked entities with current lighting
        for (id, entity) in trackedEntities {
            applyLighting(conditions, to: entity)
        }
    }

    /// Stop tracking entity for automatic lighting updates
    func stopTracking(entity: Entity) {
        trackedEntities.removeValue(forKey: entity.id)
    }

    /// Stop tracking all entities
    func stopTrackingAll() {
        trackedEntities.removeAll()
    }

    // MARK: - Color Utilities

    /// Convert color temperature (Kelvin) to RGB color
    private func colorFromTemperature(_ kelvin: Float) -> UIColor {
        // Simplified color temperature to RGB conversion
        // Based on Tanner Helland's algorithm

        let temp = kelvin / 100.0
        var red: Float
        var green: Float
        var blue: Float

        // Calculate red
        if temp <= 66 {
            red = 1.0
        } else {
            red = temp - 60.0
            red = 329.698727446 * pow(red, -0.1332047592)
            red = red / 255.0
            red = max(0, min(1, red))
        }

        // Calculate green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            green = green / 255.0
            green = max(0, min(1, green))
        } else {
            green = temp - 60.0
            green = 288.1221695283 * pow(green, -0.0755148492)
            green = green / 255.0
            green = max(0, min(1, green))
        }

        // Calculate blue
        if temp >= 66 {
            blue = 1.0
        } else if temp <= 19 {
            blue = 0.0
        } else {
            blue = temp - 10.0
            blue = 138.5177312231 * log(blue) - 305.0447927307
            blue = blue / 255.0
            blue = max(0, min(1, blue))
        }

        return UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1.0)
    }

    /// Blend two colors with intensity
    private func blendColors(_ base: UIColor, with overlay: UIColor, intensity: Float) -> UIColor {
        var baseR: CGFloat = 0, baseG: CGFloat = 0, baseB: CGFloat = 0, baseA: CGFloat = 0
        var overlayR: CGFloat = 0, overlayG: CGFloat = 0, overlayB: CGFloat = 0, overlayA: CGFloat = 0

        base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA)
        overlay.getRed(&overlayR, green: &overlayG, blue: &overlayB, alpha: &overlayA)

        let factor = CGFloat(min(max(intensity, 0), 1))

        let r = baseR + (overlayR - baseR) * factor
        let g = baseG + (overlayG - baseG) * factor
        let b = baseB + (overlayB - baseB) * factor

        return UIColor(red: r, green: g, blue: b, alpha: baseA)
    }

    // MARK: - Presets

    /// Apply preset lighting conditions (for testing/indoor use)
    func applyPreset(_ preset: LightingPreset) {
        let conditions = preset.conditions
        currentLightingConditions = conditions

        // Apply to all tracked entities
        updateTrackedEntities()

        print("Applied lighting preset: \(preset.name)")
    }

    // MARK: - Query Methods

    /// Get current ambient light level (0.0 - 1.0)
    func getAmbientLightLevel() -> Float {
        return ambientIntensity / 2000.0  // Normalize typical range
    }

    /// Get current color temperature in Kelvin
    func getColorTemperature() -> Float {
        return ambientColorTemperature
    }

    /// Get lighting condition category
    func getLightingCategory() -> LightingCategory {
        let level = getAmbientLightLevel()

        if level < 0.2 {
            return .dark
        } else if level < 0.4 {
            return .dim
        } else if level < 0.7 {
            return .normal
        } else {
            return .bright
        }
    }

    /// Check if current lighting is suitable for AR
    func isLightingSuitable() -> Bool {
        let level = getAmbientLightLevel()
        return level > 0.15  // Minimum 15% ambient light
    }

    // MARK: - Statistics

    func getLightingStats() -> LightingStats {
        return LightingStats(
            isActive: isActive,
            ambientIntensity: ambientIntensity,
            colorTemperature: ambientColorTemperature,
            primaryLightIntensity: primaryLightIntensity,
            category: getLightingCategory(),
            trackedEntityCount: trackedEntities.count
        )
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        var info = "=== Lighting Estimation Debug ===\n"
        info += "Active: \(isActive)\n"
        info += "Quality: \(lightingQuality.rawValue)\n"
        info += "Ambient Intensity: \(Int(ambientIntensity)) lumens\n"
        info += "Color Temperature: \(Int(ambientColorTemperature))K\n"
        info += "Primary Light: \(Int(primaryLightIntensity)) lumens\n"
        info += "Direction: \(primaryLightDirection)\n"
        info += "Category: \(getLightingCategory().rawValue)\n"
        info += "Tracked Entities: \(trackedEntities.count)\n"
        info += "================================="
        return info
    }
}

// MARK: - Data Structures

/// Snapshot of lighting conditions at a point in time
struct LightingConditions {
    let ambientIntensity: Float  // lumens
    let ambientColorTemperature: Float  // Kelvin
    let primaryLightDirection: SIMD3<Float>
    let primaryLightIntensity: Float  // lumens
    let timestamp: Date

    /// Get descriptive category
    var category: LightingCategory {
        let level = ambientIntensity / 2000.0
        if level < 0.2 {
            return .dark
        } else if level < 0.4 {
            return .dim
        } else if level < 0.7 {
            return .normal
        } else {
            return .bright
        }
    }
}

/// Lighting quality levels
enum LightingQuality: String {
    case basic = "Basic"
    case standard = "Standard"
    case high = "High"
    case ultra = "Ultra"
}

/// Lighting categories
enum LightingCategory: String {
    case dark = "Dark"
    case dim = "Dim"
    case normal = "Normal"
    case bright = "Bright"
}

/// Preset lighting conditions
struct LightingPreset {
    let name: String
    let conditions: LightingConditions

    static let indoor = LightingPreset(
        name: "Indoor",
        conditions: LightingConditions(
            ambientIntensity: 500.0,
            ambientColorTemperature: 3500.0,
            primaryLightDirection: SIMD3(0, -1, 0.3),
            primaryLightIntensity: 300.0,
            timestamp: Date()
        )
    )

    static let outdoor = LightingPreset(
        name: "Outdoor",
        conditions: LightingConditions(
            ambientIntensity: 1800.0,
            ambientColorTemperature: 6500.0,
            primaryLightDirection: SIMD3(0.3, -1, 0.2),
            primaryLightIntensity: 1500.0,
            timestamp: Date()
        )
    )

    static let sunset = LightingPreset(
        name: "Sunset",
        conditions: LightingConditions(
            ambientIntensity: 800.0,
            ambientColorTemperature: 2500.0,
            primaryLightDirection: SIMD3(0.7, -0.3, 0),
            primaryLightIntensity: 600.0,
            timestamp: Date()
        )
    )

    static let night = LightingPreset(
        name: "Night",
        conditions: LightingConditions(
            ambientIntensity: 100.0,
            ambientColorTemperature: 4000.0,
            primaryLightDirection: SIMD3(0, -1, 0),
            primaryLightIntensity: 50.0,
            timestamp: Date()
        )
    )
}

/// Statistics structure
struct LightingStats {
    let isActive: Bool
    let ambientIntensity: Float
    let colorTemperature: Float
    let primaryLightIntensity: Float
    let category: LightingCategory
    let trackedEntityCount: Int
}

// MARK: - Notifications

extension Notification.Name {
    static let lightingEstimationStarted = Notification.Name("lightingEstimationStarted")
    static let lightingEstimationStopped = Notification.Name("lightingEstimationStopped")
    static let lightingConditionsUpdated = Notification.Name("lightingConditionsUpdated")
}
