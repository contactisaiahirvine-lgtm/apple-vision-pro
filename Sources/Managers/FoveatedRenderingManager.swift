import Foundation
import ARKit
import Metal
import MetalKit
import simd
import RealityKit

/// Manages foveated rendering with gaze-based resolution adjustment for Vision Pro
@MainActor
class FoveatedRenderingManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var foveationLevel: FoveationLevel = .medium
    @Published var currentGazePosition: SIMD2<Float>? = nil

    // MARK: - Foveation Configuration

    enum FoveationLevel: Int, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
        case extreme = 4

        var fovealRadius: Float {
            switch self {
            case .none: return 1.0
            case .low: return 0.4
            case .medium: return 0.3
            case .high: return 0.2
            case .extreme: return 0.15
            }
        }

        var peripheralScale: Float {
            switch self {
            case .none: return 1.0
            case .low: return 0.75
            case .medium: return 0.5
            case .high: return 0.35
            case .extreme: return 0.25
            }
        }

        var transitionWidth: Float {
            switch self {
            case .none: return 0.0
            case .low: return 0.3
            case .medium: return 0.25
            case .high: return 0.2
            case .extreme: return 0.15
            }
        }
    }

    // MARK: - Gaze Tracking

    private var gazeHistory: [SIMD2<Float>] = []
    private let gazeHistorySize = 10
    private var smoothedGaze: SIMD2<Float> = SIMD2(0.5, 0.5)  // Normalized screen space

    // MARK: - Rendering Zones

    struct RenderZone {
        let center: SIMD2<Float>
        let radius: Float
        let resolution: Float  // Scale factor
        let shadingRate: MTLSize  // Metal variable rate rasterization
    }

    private var renderZones: [RenderZone] = []

    // MARK: - Metal Resources

    private weak var device: MTLDevice?
    private var variableRateShadingSupported = false

    // MARK: - Statistics

    private(set) var performanceGain: Float = 0.0  // Estimated percentage
    private(set) var pixelsSaved: UInt64 = 0
    private(set) var gazeUpdates: UInt64 = 0

    // MARK: - Initialization

    init() {
        setupMetal()
        updateRenderZones()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Failed to create Metal device for foveated rendering")
            return
        }

        self.device = device

        // Check if variable rate shading is supported
        if #available(visionOS 1.0, *) {
            variableRateShadingSupported = device.supportsFamily(.apple7) || device.supportsFamily(.apple8)
        }

        print("✅ Foveated Rendering Manager initialized (VRS: \(variableRateShadingSupported))")
    }

    // MARK: - Gaze Processing

    /// Update gaze position from ARKit
    func updateGaze(from frame: ARFrame) {
        guard isEnabled else { return }

        // Get gaze direction from ARKit
        // In real implementation, this would use ARFaceAnchor or eye tracking
        // For now, we'll use a placeholder

        // Vision Pro provides eye tracking through ARKit
        // The gaze vector can be converted to screen space coordinates

        gazeUpdates += 1

        // Update render zones based on new gaze position
        if currentGazePosition != nil {
            updateRenderZones()
        }
    }

    /// Set gaze position manually (for testing or external gaze systems)
    func setGazePosition(_ position: SIMD2<Float>) {
        // Clamp to [0, 1] range
        let clampedPosition = SIMD2<Float>(
            max(0.0, min(1.0, position.x)),
            max(0.0, min(1.0, position.y))
        )

        currentGazePosition = clampedPosition

        // Add to history for smoothing
        gazeHistory.append(clampedPosition)
        if gazeHistory.count > gazeHistorySize {
            gazeHistory.removeFirst()
        }

        // Calculate smoothed gaze
        smoothedGaze = gazeHistory.reduce(SIMD2<Float>(0, 0), +) / Float(gazeHistory.count)

        // Update render zones
        updateRenderZones()
    }

    // MARK: - Render Zone Management

    private func updateRenderZones() {
        renderZones.removeAll()

        let config = foveationLevel

        // Foveal region (high quality)
        renderZones.append(RenderZone(
            center: smoothedGaze,
            radius: config.fovealRadius,
            resolution: 1.0,
            shadingRate: MTLSize(width: 1, height: 1, depth: 1)
        ))

        // Peripheral region (reduced quality)
        renderZones.append(RenderZone(
            center: smoothedGaze,
            radius: 1.0,  // Full screen
            resolution: config.peripheralScale,
            shadingRate: MTLSize(width: 2, height: 2, depth: 1)
        ))

        // Calculate estimated performance gain
        calculatePerformanceGain()
    }

    private func calculatePerformanceGain() {
        // Estimate pixel savings from foveation
        let fovealArea = Float.pi * pow(foveationLevel.fovealRadius, 2)
        let peripheralArea = 1.0 - fovealArea
        let peripheralScale = foveationLevel.peripheralScale

        // Percentage of pixels saved
        let pixelReduction = peripheralArea * (1.0 - peripheralScale)
        performanceGain = pixelReduction * 100.0
    }

    // MARK: - Rendering Integration

    /// Get shading rate for screen position
    func getShadingRate(for screenPosition: SIMD2<Float>) -> MTLSize {
        guard isEnabled else {
            return MTLSize(width: 1, height: 1, depth: 1)
        }

        let distanceFromGaze = simd_distance(screenPosition, smoothedGaze)

        if distanceFromGaze < foveationLevel.fovealRadius {
            // High quality foveal region
            return MTLSize(width: 1, height: 1, depth: 1)
        } else if distanceFromGaze < foveationLevel.fovealRadius + foveationLevel.transitionWidth {
            // Transition region
            return MTLSize(width: 1, height: 2, depth: 1)
        } else {
            // Peripheral region - lower quality
            return MTLSize(width: 2, height: 2, depth: 1)
        }
    }

    /// Get resolution scale for screen position
    func getResolutionScale(for screenPosition: SIMD2<Float>) -> Float {
        guard isEnabled else { return 1.0 }

        let distanceFromGaze = simd_distance(screenPosition, smoothedGaze)

        if distanceFromGaze < foveationLevel.fovealRadius {
            return 1.0
        } else if distanceFromGaze < foveationLevel.fovealRadius + foveationLevel.transitionWidth {
            // Smooth transition
            let t = (distanceFromGaze - foveationLevel.fovealRadius) / foveationLevel.transitionWidth
            return simd_mix(1.0, foveationLevel.peripheralScale, t)
        } else {
            return foveationLevel.peripheralScale
        }
    }

    /// Apply foveated rendering to Metal render pass
    func configureFoveatedRenderPass(
        descriptor: MTLRenderPassDescriptor,
        commandEncoder: MTLRenderCommandEncoder?
    ) {
        guard isEnabled, variableRateShadingSupported else { return }

        // In a real implementation, this would configure variable rate shading
        // using Metal's fragment shading rate API

        // For now, this is a placeholder that would integrate with Metal rendering
    }

    // MARK: - Control

    /// Set foveation level
    func setFoveationLevel(_ level: FoveationLevel) {
        foveationLevel = level
        updateRenderZones()
        print("Foveation level: \(level) (Gain: \(String(format: "%.1f", performanceGain))%)")
    }

    /// Enable/disable foveated rendering
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            updateRenderZones()
        }
        print("Foveated rendering: \(enabled)")
    }

    /// Reset gaze history
    func resetGazeHistory() {
        gazeHistory.removeAll()
        smoothedGaze = SIMD2(0.5, 0.5)
        currentGazePosition = nil
        print("Gaze history reset")
    }

    // MARK: - Statistics

    func getFoveationStats() -> FoveationStats {
        return FoveationStats(
            isEnabled: isEnabled,
            foveationLevel: foveationLevel,
            gazePosition: currentGazePosition,
            smoothedGaze: smoothedGaze,
            performanceGain: performanceGain,
            pixelsSaved: pixelsSaved,
            gazeUpdates: gazeUpdates,
            renderZones: renderZones.count,
            vrsSupported: variableRateShadingSupported
        )
    }

    func resetStats() {
        pixelsSaved = 0
        gazeUpdates = 0
        performanceGain = 0
        print("Foveation stats reset")
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        let stats = getFoveationStats()

        var info = "=== Foveated Rendering ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Level: \(stats.foveationLevel)\n"
        info += "VRS Supported: \(stats.vrsSupported)\n"

        if let gaze = stats.gazePosition {
            info += "Gaze Position: (\(String(format: "%.3f", gaze.x)), \(String(format: "%.3f", gaze.y)))\n"
        } else {
            info += "Gaze Position: None\n"
        }

        info += "Smoothed Gaze: (\(String(format: "%.3f", stats.smoothedGaze.x)), \(String(format: "%.3f", stats.smoothedGaze.y)))\n"
        info += "Performance Gain: \(String(format: "%.1f", stats.performanceGain))%\n"
        info += "Gaze Updates: \(stats.gazeUpdates)\n"
        info += "Render Zones: \(stats.renderZones)\n"
        info += "Foveal Radius: \(String(format: "%.2f", foveationLevel.fovealRadius))\n"
        info += "Peripheral Scale: \(String(format: "%.2f", foveationLevel.peripheralScale))\n"
        info += "======================="

        return info
    }

    /// Visualize foveation zones (for debugging)
    func getVisualizationData() -> FoveationVisualization {
        return FoveationVisualization(
            gazeCenter: smoothedGaze,
            fovealRadius: foveationLevel.fovealRadius,
            transitionWidth: foveationLevel.transitionWidth,
            peripheralScale: foveationLevel.peripheralScale
        )
    }
}

// MARK: - Supporting Types

struct FoveationStats {
    let isEnabled: Bool
    let foveationLevel: FoveatedRenderingManager.FoveationLevel
    let gazePosition: SIMD2<Float>?
    let smoothedGaze: SIMD2<Float>
    let performanceGain: Float
    let pixelsSaved: UInt64
    let gazeUpdates: UInt64
    let renderZones: Int
    let vrsSupported: Bool
}

struct FoveationVisualization {
    let gazeCenter: SIMD2<Float>
    let fovealRadius: Float
    let transitionWidth: Float
    let peripheralScale: Float
}
