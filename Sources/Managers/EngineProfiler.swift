import Foundation
import Metal
import simd

/// Integrated CPU/GPU profiler for performance monitoring
@MainActor
class EngineProfiler: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = false
    @Published var isProfiling = false

    // MARK: - Profile Data

    struct ProfileFrame {
        let frameNumber: UInt64
        let timestamp: Date
        let systemTimes: [String: TimeInterval]
        let gpuPasses: [GPUPass]
        let memorySnapshot: MemorySnapshot

        struct GPUPass {
            let name: String
            let duration: TimeInterval
            let drawCalls: Int
        }

        struct MemorySnapshot {
            let used: Int64
            let textures: Int64
            let buffers: Int64
        }
    }

    // MARK: - Profiling State

    private var profiledFrames: [ProfileFrame] = []
    private let maxProfileFrames = 600  // 10 seconds at 60 FPS

    private var systemTimers: [String: CFTimeInterval] = [:]
    private var systemDurations: [String: TimeInterval] = [:]

    // MARK: - Metal Profiling

    private weak var device: MTLDevice?
    private var gpuPassTimings: [String: TimeInterval] = [:]

    // MARK: - Memory Tracking

    private var memoryBaseline: Int64 = 0

    // MARK: - Statistics

    private(set) var framesProfiled: UInt64 = 0
    private(set) var totalProfilingTime: TimeInterval = 0

    // MARK: - Initialization

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
        }

        captureMemoryBaseline()

        print("✅ Engine Profiler initialized")
    }

    // MARK: - Profiling Control

    /// Start profiling
    func startProfiling() {
        guard !isProfiling else { return }

        isProfiling = true
        isEnabled = true
        profiledFrames.removeAll()
        framesProfiled = 0

        print("Started profiling")
    }

    /// Stop profiling
    func stopProfiling() {
        isProfiling = false
        print("Stopped profiling (\(framesProfiled) frames)")
    }

    // MARK: - System Timing

    /// Begin timing a system
    func beginSystem(_ name: String) {
        guard isEnabled else { return }
        systemTimers[name] = CACurrentMediaTime()
    }

    /// End timing a system
    func endSystem(_ name: String) {
        guard isEnabled,
              let startTime = systemTimers[name] else {
            return
        }

        let duration = CACurrentMediaTime() - startTime
        systemDurations[name] = duration
        systemTimers.removeValue(forKey: name)
    }

    // MARK: - GPU Pass Timing

    /// Record GPU pass duration
    func recordGPUPass(name: String, duration: TimeInterval, drawCalls: Int = 0) {
        guard isEnabled else { return }
        gpuPassTimings[name] = duration
    }

    // MARK: - Frame Capture

    /// Capture current frame profile
    func captureFrame() {
        guard isProfiling else { return }

        let memorySnapshot = captureMemorySnapshot()

        let gpuPasses = gpuPassTimings.map { name, duration in
            ProfileFrame.GPUPass(name: name, duration: duration, drawCalls: 0)
        }

        let frame = ProfileFrame(
            frameNumber: framesProfiled,
            timestamp: Date(),
            systemTimes: systemDurations,
            gpuPasses: gpuPasses,
            memorySnapshot: memorySnapshot
        )

        profiledFrames.append(frame)
        framesProfiled += 1

        if profiledFrames.count > maxProfileFrames {
            profiledFrames.removeFirst()
        }

        // Clear for next frame
        systemDurations.removeAll()
        gpuPassTimings.removeAll()
    }

    // MARK: - Memory Profiling

    private func captureMemoryBaseline() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        memoryBaseline = kerr == KERN_SUCCESS ? Int64(taskInfo.resident_size) : 0
    }

    private func captureMemorySnapshot() -> ProfileFrame.MemorySnapshot {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let usedMemory = kerr == KERN_SUCCESS ? Int64(taskInfo.resident_size) : 0

        return ProfileFrame.MemorySnapshot(
            used: usedMemory,
            textures: 0,  // Would query Metal
            buffers: 0
        )
    }

    // MARK: - Analysis

    /// Get average system times
    func getAverageSystemTimes() -> [String: TimeInterval] {
        guard !profiledFrames.isEmpty else { return [:] }

        var totals: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]

        for frame in profiledFrames {
            for (system, time) in frame.systemTimes {
                totals[system, default: 0] += time
                counts[system, default: 0] += 1
            }
        }

        return totals.mapValues { total in
            let count = counts.first(where: { $0.key == totals.firstIndex(where: { $0.value == total })?.key })?.value ?? 1
            return total / Double(count)
        }
    }

    /// Get frame time percentiles
    func getFrameTimePercentiles() -> (p50: TimeInterval, p95: TimeInterval, p99: TimeInterval) {
        guard !profiledFrames.isEmpty else { return (0, 0, 0) }

        let frameTimes = profiledFrames.map { frame in
            frame.systemTimes.values.reduce(0, +)
        }.sorted()

        let count = frameTimes.count

        return (
            p50: frameTimes[count * 50 / 100],
            p95: frameTimes[count * 95 / 100],
            p99: frameTimes[count * 99 / 100]
        )
    }

    /// Get memory usage over time
    func getMemoryHistory() -> [Int64] {
        return profiledFrames.map { $0.memorySnapshot.used }
    }

    // MARK: - Export

    /// Export profile data to JSON
    func exportProfileData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Would encode profiledFrames
        // For now, return placeholder
        return nil
    }

    // MARK: - Statistics

    func getProfilerStats() -> ProfilerStats {
        let avgSysTimes = getAverageSystemTimes()
        let percentiles = getFrameTimePercentiles()

        let currentMemory = profiledFrames.last?.memorySnapshot.used ?? 0

        return ProfilerStats(
            isEnabled: isEnabled,
            isProfiling: isProfiling,
            framesProfiled: Int(framesProfiled),
            averageSystemTimes: avgSysTimes,
            frameTimeP50: percentiles.p50,
            frameTimeP95: percentiles.p95,
            frameTimeP99: percentiles.p99,
            currentMemory: currentMemory,
            memoryBaseline: memoryBaseline
        )
    }

    func getDebugInfo() -> String {
        let stats = getProfilerStats()

        var info = "=== Engine Profiler ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Profiling: \(stats.isProfiling ? "Active" : "Inactive")\n"
        info += "Frames: \(stats.framesProfiled)\n"

        if !stats.averageSystemTimes.isEmpty {
            info += "\nAverage System Times:\n"
            for (system, time) in stats.averageSystemTimes.sorted(by: { $0.value > $1.value }) {
                info += "  \(system): \(String(format: "%.2f", time * 1000))ms\n"
            }
        }

        info += "\nFrame Times:\n"
        info += "  P50: \(String(format: "%.2f", stats.frameTimeP50 * 1000))ms\n"
        info += "  P95: \(String(format: "%.2f", stats.frameTimeP95 * 1000))ms\n"
        info += "  P99: \(String(format: "%.2f", stats.frameTimeP99 * 1000))ms\n"

        info += "\nMemory:\n"
        info += "  Current: \(ByteCountFormatter.string(fromByteCount: stats.currentMemory, countStyle: .memory))\n"
        info += "  Baseline: \(ByteCountFormatter.string(fromByteCount: stats.memoryBaseline, countStyle: .memory))\n"

        info += "====================="

        return info
    }
}

struct ProfilerStats {
    let isEnabled: Bool
    let isProfiling: Bool
    let framesProfiled: Int
    let averageSystemTimes: [String: TimeInterval]
    let frameTimeP50: TimeInterval
    let frameTimeP95: TimeInterval
    let frameTimeP99: TimeInterval
    let currentMemory: Int64
    let memoryBaseline: Int64
}
