import Foundation
import Metal
import MetalKit
import RealityKit
import Combine

/// Manages GPU frame pacing and dynamically adjusts rendering quality to maintain target frame rate
@MainActor
class GPUFramePacingManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = true
    @Published var targetFrameTime: TimeInterval = 1.0 / 90.0  // 90 FPS for Vision Pro
    @Published var currentGPUTime: TimeInterval = 0.0
    @Published var currentQualityLevel: QualityLevel = .high

    // MARK: - Performance Metrics

    private var gpuFrameTimes: [TimeInterval] = []
    private let smoothingWindowSize = 30
    private var averageGPUTime: TimeInterval = 0.0

    // MARK: - Quality Settings

    enum QualityLevel: Int, CaseIterable {
        case low = 0
        case medium = 1
        case high = 2
        case ultra = 3

        var renderScale: Float {
            switch self {
            case .low: return 0.5
            case .medium: return 0.75
            case .high: return 1.0
            case .ultra: return 1.25
            }
        }

        var shaderLOD: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            case .ultra: return 3
            }
        }

        var maxDrawCalls: Int {
            switch self {
            case .low: return 500
            case .medium: return 1000
            case .high: return 2000
            case .ultra: return 4000
            }
        }
    }

    // MARK: - Configuration

    var autoAdjustQuality = true
    var qualityAdjustmentThreshold: TimeInterval = 0.002  // 2ms over budget
    var renderScale: Float = 1.0
    var shaderLOD: Int = 2
    var maxDrawCalls: Int = 2000

    // MARK: - Metal Resources

    private weak var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var gpuStartTime: CFTimeInterval = 0
    private var gpuEndTime: CFTimeInterval = 0

    // MARK: - Statistics

    private(set) var frameCount: UInt64 = 0
    private(set) var droppedFrames: UInt64 = 0
    private(set) var qualityAdjustments: UInt64 = 0

    // MARK: - Initialization

    init() {
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Failed to create Metal device")
            return
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        print("✅ GPU Frame Pacing initialized with target: \(Int(1.0 / targetFrameTime)) FPS")
    }

    // MARK: - Frame Timing

    /// Begin GPU timing for current frame
    func beginFrame() {
        guard isEnabled else { return }
        gpuStartTime = CACurrentMediaTime()
    }

    /// End GPU timing and adjust quality if needed
    func endFrame() {
        guard isEnabled else { return }

        gpuEndTime = CACurrentMediaTime()
        let frameTime = gpuEndTime - gpuStartTime

        currentGPUTime = frameTime
        frameCount += 1

        // Update moving average
        gpuFrameTimes.append(frameTime)
        if gpuFrameTimes.count > smoothingWindowSize {
            gpuFrameTimes.removeFirst()
        }

        averageGPUTime = gpuFrameTimes.reduce(0.0, +) / Double(gpuFrameTimes.count)

        // Check if we need to adjust quality
        if autoAdjustQuality {
            adjustQualityIfNeeded()
        }

        // Track dropped frames
        if frameTime > targetFrameTime {
            droppedFrames += 1
        }
    }

    // MARK: - Quality Adjustment

    private func adjustQualityIfNeeded() {
        let budget = targetFrameTime
        let difference = averageGPUTime - budget

        // Frame time too high - reduce quality
        if difference > qualityAdjustmentThreshold {
            if currentQualityLevel.rawValue > 0 {
                let newLevel = QualityLevel(rawValue: currentQualityLevel.rawValue - 1)!
                setQualityLevel(newLevel)
                qualityAdjustments += 1
                print("⚠️ GPU over budget by \(Int(difference * 1000))ms - reducing to \(newLevel)")
            }
        }
        // Frame time comfortably under budget - increase quality
        else if difference < -qualityAdjustmentThreshold * 2 {
            if currentQualityLevel.rawValue < QualityLevel.allCases.count - 1 {
                let newLevel = QualityLevel(rawValue: currentQualityLevel.rawValue + 1)!
                setQualityLevel(newLevel)
                qualityAdjustments += 1
                print("✅ GPU under budget - increasing to \(newLevel)")
            }
        }
    }

    /// Manually set quality level
    func setQualityLevel(_ level: QualityLevel) {
        currentQualityLevel = level
        renderScale = level.renderScale
        shaderLOD = level.shaderLOD
        maxDrawCalls = level.maxDrawCalls

        // Post notification for rendering systems to adjust
        NotificationCenter.default.post(
            name: .qualityLevelChanged,
            object: nil,
            userInfo: [
                "level": level,
                "renderScale": renderScale,
                "shaderLOD": shaderLOD,
                "maxDrawCalls": maxDrawCalls
            ]
        )
    }

    // MARK: - GPU Time Queries

    /// Get GPU time for specific command buffer
    func measureGPUTime(commandBuffer: MTLCommandBuffer, completion: @escaping (TimeInterval) -> Void) {
        let startTime = CACurrentMediaTime()

        commandBuffer.addCompletedHandler { _ in
            let endTime = CACurrentMediaTime()
            let gpuTime = endTime - startTime
            Task { @MainActor in
                completion(gpuTime)
            }
        }
    }

    // MARK: - Statistics

    /// Get current performance statistics
    func getPerformanceStats() -> PerformanceStats {
        return PerformanceStats(
            averageGPUTime: averageGPUTime,
            currentGPUTime: currentGPUTime,
            targetFrameTime: targetFrameTime,
            frameCount: frameCount,
            droppedFrames: droppedFrames,
            dropRate: Double(droppedFrames) / Double(max(frameCount, 1)),
            qualityLevel: currentQualityLevel,
            qualityAdjustments: qualityAdjustments,
            renderScale: renderScale,
            shaderLOD: shaderLOD,
            maxDrawCalls: maxDrawCalls
        )
    }

    /// Get frame time percentiles
    func getFrameTimePercentiles() -> FrameTimePercentiles {
        guard !gpuFrameTimes.isEmpty else {
            return FrameTimePercentiles(p50: 0, p95: 0, p99: 0, max: 0)
        }

        let sorted = gpuFrameTimes.sorted()
        let count = sorted.count

        return FrameTimePercentiles(
            p50: sorted[count * 50 / 100],
            p95: sorted[count * 95 / 100],
            p99: sorted[count * 99 / 100],
            max: sorted[count - 1]
        )
    }

    // MARK: - Control

    /// Reset statistics
    func resetStats() {
        frameCount = 0
        droppedFrames = 0
        qualityAdjustments = 0
        gpuFrameTimes.removeAll()
        averageGPUTime = 0.0
        print("GPU frame pacing stats reset")
    }

    /// Enable/disable auto quality adjustment
    func setAutoAdjustQuality(_ enabled: Bool) {
        autoAdjustQuality = enabled
        print("Auto quality adjustment: \(enabled)")
    }

    /// Set target frame rate
    func setTargetFrameRate(_ fps: Int) {
        targetFrameTime = 1.0 / Double(fps)
        print("Target frame rate: \(fps) FPS (\(Int(targetFrameTime * 1000))ms)")
    }

    // MARK: - Debug

    func getDebugInfo() -> String {
        let stats = getPerformanceStats()
        let percentiles = getFrameTimePercentiles()

        var info = "=== GPU Frame Pacing ===\n"
        info += "Status: \(isEnabled ? "Enabled" : "Disabled")\n"
        info += "Quality: \(stats.qualityLevel) (Scale: \(String(format: "%.2f", stats.renderScale))x)\n"
        info += "Target: \(Int(1.0 / targetFrameTime)) FPS (\(String(format: "%.2f", targetFrameTime * 1000))ms)\n"
        info += "Current: \(String(format: "%.2f", stats.currentGPUTime * 1000))ms\n"
        info += "Average: \(String(format: "%.2f", stats.averageGPUTime * 1000))ms\n"
        info += "Frames: \(stats.frameCount) (Dropped: \(stats.droppedFrames), \(String(format: "%.1f", stats.dropRate * 100))%)\n"
        info += "Quality Adjustments: \(stats.qualityAdjustments)\n"
        info += "Frame Times - P50: \(String(format: "%.2f", percentiles.p50 * 1000))ms, P95: \(String(format: "%.2f", percentiles.p95 * 1000))ms, P99: \(String(format: "%.2f", percentiles.p99 * 1000))ms\n"
        info += "Shader LOD: \(stats.shaderLOD)\n"
        info += "Max Draw Calls: \(stats.maxDrawCalls)\n"
        info += "======================="

        return info
    }
}

// MARK: - Supporting Types

struct PerformanceStats {
    let averageGPUTime: TimeInterval
    let currentGPUTime: TimeInterval
    let targetFrameTime: TimeInterval
    let frameCount: UInt64
    let droppedFrames: UInt64
    let dropRate: Double
    let qualityLevel: GPUFramePacingManager.QualityLevel
    let qualityAdjustments: UInt64
    let renderScale: Float
    let shaderLOD: Int
    let maxDrawCalls: Int
}

struct FrameTimePercentiles {
    let p50: TimeInterval  // Median
    let p95: TimeInterval
    let p99: TimeInterval
    let max: TimeInterval
}

// MARK: - Notifications

extension Notification.Name {
    static let qualityLevelChanged = Notification.Name("qualityLevelChanged")
}
