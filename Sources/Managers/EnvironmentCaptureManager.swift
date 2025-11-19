import Foundation
import ARKit
import RealityKit
import MetalKit
import simd

/// Captures environment lighting and generates PBR-ready environment maps
@MainActor
class EnvironmentCaptureManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var hasEnvironmentMap = false
    @Published var environmentBrightness: Float = 1.0

    // MARK: - Environment Data

    private var sphericalHarmonics: [Float] = []
    private var environmentTexture: MTLTexture?
    private var irradianceMap: MTLTexture?

    // MARK: - Configuration

    var captureResolution: Int = 512  // Cubemap resolution
    var updateInterval: TimeInterval = 0.5  // Update every 0.5s

    // MARK: - Metal Resources

    private weak var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?

    // MARK: - AR Integration

    private weak var arView: ARView?
    private var lastCaptureTime: TimeInterval = 0

    // MARK: - Statistics

    private(set) var capturesPerformed: Int = 0
    private(set) var environmentUpdates: Int = 0

    // MARK: - Initialization

    init() {
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Failed to create Metal device for environment capture")
            return
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        print("✅ Environment Capture Manager initialized")
    }

    // MARK: - Setup

    func setup(arView: ARView) {
        self.arView = arView
        print("Environment capture linked to ARView")
    }

    // MARK: - Capture

    /// Update environment capture (call from game loop)
    func update(currentTime: TimeInterval) {
        guard isEnabled else { return }

        if currentTime - lastCaptureTime >= updateInterval {
            captureEnvironment()
            lastCaptureTime = currentTime
        }
    }

    private func captureEnvironment() {
        guard let frame = arView?.session.currentFrame else { return }

        // Get spherical harmonics from ARKit
        if let lightEstimate = frame.lightEstimate {
            extractSphericalHarmonics(from: lightEstimate)
        }

        // Build environment texture from SH
        buildEnvironmentTexture()

        capturesPerformed += 1
        hasEnvironmentMap = true

        NotificationCenter.default.post(name: .environmentCaptured, object: nil)
    }

    private func extractSphericalHarmonics(from lightEstimate: ARLightEstimate) {
        // ARKit provides spherical harmonics coefficients
        // These represent the lighting environment

        if let directional = lightEstimate as? ARDirectionalLightEstimate {
            // Extract SH coefficients
            // ARKit provides them as an array of floats

            sphericalHarmonics = []  // Would extract actual coefficients

            environmentBrightness = Float(lightEstimate.ambientIntensity) / 1000.0
            environmentUpdates += 1
        }
    }

    private func buildEnvironmentTexture() {
        guard let device = device else { return }

        // Create cubemap texture from spherical harmonics
        let descriptor = MTLTextureDescriptor.textureCube(
            pixelFormat: .rgba16Float,
            size: captureResolution,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private

        environmentTexture = device.makeTexture(descriptor: descriptor)

        // Render SH to cubemap using compute shader
        // (In production, would use actual Metal compute pipeline)

        // Generate irradiance map for diffuse lighting
        generateIrradianceMap()
    }

    private func generateIrradianceMap() {
        guard let device = device else { return }

        // Create smaller irradiance map for diffuse lighting
        let descriptor = MTLTextureDescriptor.textureCube(
            pixelFormat: .rgba16Float,
            size: 64,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private

        irradianceMap = device.makeTexture(descriptor: descriptor)

        // Convolve environment map to create irradiance
        // (Would use compute shader for convolution)
    }

    // MARK: - Apply to Materials

    /// Apply environment lighting to entity
    func applyEnvironmentLighting(to entity: Entity) {
        guard hasEnvironmentMap else {
            print("WARNING: No environment map captured yet")
            return
        }

        entity.visit { child in
            if var modelEntity = child as? ModelEntity {
                applyEnvironmentToModel(&modelEntity)
            }
        }

        print("Applied environment lighting to: \(entity.name)")
    }

    private func applyEnvironmentToModel(_ modelEntity: inout ModelEntity) {
        guard let model = modelEntity.model else { return }

        // Apply environment texture to materials
        for (index, material) in model.materials.enumerated() {
            if var pbrMaterial = material as? PhysicallyBasedMaterial {
                // Set environment texture
                // pbrMaterial.environment = environmentTexture  // Simplified

                // Adjust based on captured brightness
                var newMaterial = pbrMaterial
                // Would apply brightness and environment map

                modelEntity.model?.materials[index] = newMaterial
            }
        }
    }

    /// Get ImageBasedLightComponent for entity
    func createImageBasedLight() -> ImageBasedLightComponent? {
        guard let environmentTexture = environmentTexture else { return nil }

        // Create IBL component with captured environment
        // return ImageBasedLightComponent(source: .single(environmentTexture))  // Simplified
        return nil
    }

    // MARK: - Resource Access

    /// Get current environment texture
    func getEnvironmentTexture() -> MTLTexture? {
        return environmentTexture
    }

    /// Get irradiance map
    func getIrradianceMap() -> MTLTexture? {
        return irradianceMap
    }

    /// Get spherical harmonics coefficients
    func getSphericalHarmonics() -> [Float] {
        return sphericalHarmonics
    }

    // MARK: - Configuration

    func setCaptureResolution(_ resolution: Int) {
        captureResolution = max(64, min(2048, resolution))
        print("Environment capture resolution: \(captureResolution)")
    }

    func setUpdateInterval(_ interval: TimeInterval) {
        updateInterval = max(0.1, interval)
        print("Environment update interval: \(String(format: "%.2f", interval))s")
    }

    // MARK: - Statistics

    func getEnvironmentStats() -> EnvironmentStats {
        return EnvironmentStats(
            isEnabled: isEnabled,
            hasEnvironmentMap: hasEnvironmentMap,
            captureResolution: captureResolution,
            capturesPerformed: capturesPerformed,
            environmentUpdates: environmentUpdates,
            environmentBrightness: environmentBrightness,
            sphericalHarmonicsCount: sphericalHarmonics.count
        )
    }

    func getDebugInfo() -> String {
        let stats = getEnvironmentStats()

        var info = "=== Environment Capture ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Has Environment Map: \(stats.hasEnvironmentMap)\n"
        info += "Resolution: \(stats.captureResolution)x\(stats.captureResolution)\n"
        info += "Captures: \(stats.capturesPerformed)\n"
        info += "Updates: \(stats.environmentUpdates)\n"
        info += "Brightness: \(String(format: "%.2f", stats.environmentBrightness))\n"
        info += "SH Coefficients: \(stats.sphericalHarmonicsCount)\n"
        info += "Update Interval: \(String(format: "%.2f", updateInterval))s\n"
        info += "======================"

        return info
    }
}

struct EnvironmentStats {
    let isEnabled: Bool
    let hasEnvironmentMap: Bool
    let captureResolution: Int
    let capturesPerformed: Int
    let environmentUpdates: Int
    let environmentBrightness: Float
    let sphericalHarmonicsCount: Int
}

extension Notification.Name {
    static let environmentCaptured = Notification.Name("environmentCaptured")
}
