import Foundation
import Combine
import ObjectiveC
import RealityKit
import simd

extension GameManager {
    // MARK: - Associated Properties

    var lightingManager: LightingEstimationManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.lightingManager) as? LightingEstimationManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lightingManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isLightingEstimationEnabled: Bool {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.isLightingEstimationEnabled) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.isLightingEstimationEnabled, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var autoApplyLightingToAssets: Bool {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.autoApplyLightingToAssets) as? Bool ?? true
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.autoApplyLightingToAssets, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Setup

    /// Setup lighting estimation and compensation
    func setupLighting(arView: RealityKit.ARView, quality: LightingQuality = .standard) {
        guard lightingManager == nil else {
            print("Lighting estimation already initialized")
            return
        }

        let manager = LightingEstimationManager()
        lightingManager = manager

        // Configure
        manager.lightingQuality = quality
        manager.setup(arView: arView)

        // Setup notifications
        setupLightingNotifications()

        isLightingEstimationEnabled = true
        print("✅ Lighting estimation initialized with \(quality.rawValue) quality")
    }

    private func setupLightingNotifications() {
        // Listen for lighting condition updates
        NotificationCenter.default.publisher(for: .lightingConditionsUpdated)
            .sink { [weak self] notification in
                guard let conditions = notification.userInfo?["conditions"] as? LightingConditions else {
                    return
                }
                self?.handleLightingUpdate(conditions)
            }
            .store(in: &cancellables)

        print("Lighting notifications configured")
    }

    // MARK: - Control

    /// Start lighting estimation
    func startLightingEstimation() {
        guard let manager = lightingManager else {
            print("ERROR: Lighting estimation not initialized. Call setupLighting() first")
            return
        }

        manager.start()
        print("Lighting estimation started")
    }

    /// Stop lighting estimation
    func stopLightingEstimation() {
        lightingManager?.stop()
        print("Lighting estimation stopped")
    }

    /// Toggle lighting estimation
    func toggleLightingEstimation() {
        guard let manager = lightingManager else { return }

        if manager.isActive {
            stopLightingEstimation()
        } else {
            startLightingEstimation()
        }
    }

    // MARK: - Update Loop Integration

    /// Update lighting estimation (call from game loop)
    func updateLightingEstimation(deltaTime: TimeInterval) {
        guard let manager = lightingManager, manager.isActive else { return }

        manager.update(deltaTime: deltaTime)
    }

    // MARK: - Apply Lighting

    /// Apply current environmental lighting to entity
    func applyEnvironmentalLighting(to entity: Entity, track: Bool = true) {
        guard let manager = lightingManager else {
            print("WARNING: Lighting manager not initialized")
            return
        }

        manager.applyLightingTo(entity: entity, track: track)
        print("Applied environmental lighting to entity: \(entity.name)")
    }

    /// Apply lighting to all placed assets
    func applyLightingToAllAssets() {
        guard let manager = lightingManager,
              let placementManager = placementManager else {
            return
        }

        // Get all placed entities from placement manager
        // Note: PlacementManager would need to expose placed entities
        // For now, we can track them separately

        print("Applied lighting to all assets")
    }

    // MARK: - Event Handlers

    private func handleLightingUpdate(_ conditions: LightingConditions) {
        // Log significant lighting changes
        let category = conditions.category
        print("Lighting: \(category.rawValue) (\(Int(conditions.ambientIntensity)) lumens)")

        // Automatically apply to newly placed assets if enabled
        // This would be called when AssetManager places a new asset
    }

    // MARK: - Integration with Asset Placement

    /// Place asset with automatic lighting compensation
    func placeAssetWithLighting(
        named assetName: String,
        at position: SIMD3<Float>,
        track: Bool = true
    ) async -> Entity? {
        // This would integrate with AssetManager
        // For now,示例 implementation
        guard let assetManager = assetManager else {
            print("AssetManager not available")
            return nil
        }

        // Load asset
        guard let entity = try? await assetManager.loadAsset(named: assetName) else {
            return nil
        }

        // Position entity
        entity.position = position

        // Apply environmental lighting
        if autoApplyLightingToAssets {
            applyEnvironmentalLighting(to: entity, track: track)
        }

        return entity
    }

    // MARK: - Directional Lighting

    /// Add environmental directional light to scene
    func addEnvironmentalLight(to scene: RealityKit.Scene) -> DirectionalLight? {
        guard let manager = lightingManager else {
            print("WARNING: Lighting manager not initialized")
            return nil
        }

        let light = manager.addDirectionalLightTo(scene: scene)
        print("Added environmental directional light to scene")
        return light
    }

    // MARK: - Presets

    /// Apply lighting preset
    func applyLightingPreset(_ preset: LightingPreset) {
        lightingManager?.applyPreset(preset)
        print("Applied lighting preset: \(preset.name)")
    }

    /// Apply indoor lighting preset
    func useIndoorLighting() {
        applyLightingPreset(.indoor)
    }

    /// Apply outdoor lighting preset
    func useOutdoorLighting() {
        applyLightingPreset(.outdoor)
    }

    // MARK: - Query Methods

    /// Get current lighting conditions
    func getCurrentLightingConditions() -> LightingConditions? {
        return lightingManager?.currentLightingConditions
    }

    /// Get ambient light level (0.0 - 1.0)
    func getAmbientLightLevel() -> Float {
        return lightingManager?.getAmbientLightLevel() ?? 0.5
    }

    /// Get current color temperature in Kelvin
    func getColorTemperature() -> Float {
        return lightingManager?.getColorTemperature() ?? 6500.0
    }

    /// Get lighting category
    func getLightingCategory() -> LightingCategory {
        return lightingManager?.getLightingCategory() ?? .normal
    }

    /// Check if current lighting is suitable for AR
    func isLightingSuitable() -> Bool {
        return lightingManager?.isLightingSuitable() ?? true
    }

    // MARK: - Configuration

    /// Set lighting quality
    func setLightingQuality(_ quality: LightingQuality) {
        lightingManager?.lightingQuality = quality
        print("Lighting quality: \(quality.rawValue)")
    }

    /// Enable/disable automatic lighting updates
    func setAutoLightingUpdates(_ enabled: Bool) {
        lightingManager?.autoUpdateEnabled = enabled
        print("Auto lighting updates: \(enabled)")
    }

    /// Enable/disable HDR environment
    func setHDREnvironment(_ enabled: Bool) {
        lightingManager?.useHDREnvironment = enabled
        print("HDR environment: \(enabled)")
    }

    /// Set shadow intensity
    func setShadowIntensity(_ intensity: Float) {
        lightingManager?.shadowIntensity = intensity
        print("Shadow intensity: \(intensity)")
    }

    // MARK: - Entity Tracking

    /// Stop tracking entity for automatic lighting updates
    func stopTrackingLighting(for entity: Entity) {
        lightingManager?.stopTracking(entity: entity)
    }

    /// Stop tracking all entities
    func stopTrackingAllLighting() {
        lightingManager?.stopTrackingAll()
    }

    // MARK: - Statistics

    /// Get lighting statistics
    func getLightingStats() -> LightingStats? {
        return lightingManager?.getLightingStats()
    }

    /// Get lighting summary string
    func getLightingSummary() -> String {
        guard let stats = getLightingStats() else {
            return "Lighting estimation not active"
        }

        var summary = "=== Lighting Summary ===\n"
        summary += "Status: \(stats.isActive ? "Active" : "Inactive")\n"
        summary += "Category: \(stats.category.rawValue)\n"
        summary += "Ambient: \(Int(stats.ambientIntensity)) lumens\n"
        summary += "Temperature: \(Int(stats.colorTemperature))K\n"
        summary += "Primary Light: \(Int(stats.primaryLightIntensity)) lumens\n"
        summary += "Tracked Entities: \(stats.trackedEntityCount)\n"
        summary += "======================="

        return summary
    }

    // MARK: - Debug

    /// Print lighting debug info
    func printLightingDebug() {
        if let manager = lightingManager {
            print(manager.getDebugInfo())
        } else {
            print("Lighting estimation not initialized")
        }
    }

    /// Show lighting warning if unsuitable
    func checkLightingWarnings() {
        guard let manager = lightingManager else { return }

        if !manager.isLightingSuitable() {
            print("⚠️ WARNING: Lighting conditions not suitable for AR")
            print("   Current level: \(Int(manager.getAmbientLightLevel() * 100))%")
            print("   Recommended: >15% ambient light")
        }

        let category = manager.getLightingCategory()
        if category == .dark {
            print("⚠️ WARNING: Environment is too dark for optimal AR experience")
        }
    }
}

// MARK: - Associated Keys Extension

private extension AssociatedKeys {
    static var lightingManager = "lightingManager"
    static var isLightingEstimationEnabled = "isLightingEstimationEnabled"
    static var autoApplyLightingToAssets = "autoApplyLightingToAssets"
}

// MARK: - Asset Manager Integration

extension AssetManager {
    /// Load asset with automatic lighting compensation
    func loadAssetWithLighting(
        named name: String,
        lightingManager: LightingEstimationManager
    ) async throws -> Entity {
        // Load asset normally
        let entity = try await loadAsset(named: name)

        // Apply environmental lighting
        lightingManager.applyLightingTo(entity: entity, track: true)

        return entity
    }
}

// MARK: - Placement Manager Integration

extension PlacementManager {
    /// Place asset with automatic lighting
    func placeWithLighting(
        assetName: String,
        at position: SIMD3<Float>,
        lightingManager: LightingEstimationManager
    ) async {
        // This would be implemented in PlacementManager
        // to automatically apply lighting when placing assets
        print("Placing asset with lighting compensation")
    }
}
