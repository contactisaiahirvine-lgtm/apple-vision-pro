import Foundation
import Metal
import simd
import Combine

/// Streams real-time telemetry data for remote debugging
@MainActor
class RemoteTelemetryManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled = false
    @Published var isConnected = false
    @Published var remoteEndpoint: String?

    // MARK: - Telemetry Data

    struct TelemetrySnapshot: Codable {
        let timestamp: Date
        let transforms: [TransformTelemetry]
        let logs: [LogEntry]
        let performance: PerformanceMetrics
        let memory: MemoryMetrics
    }

    struct TransformTelemetry: Codable {
        let entityID: String
        let position: SIMD3<Float>
        let rotation: simd_quatf
    }

    struct LogEntry: Codable {
        let timestamp: Date
        let level: LogLevel
        let message: String
        let category: String
    }

    enum LogLevel: String, Codable {
        case debug, info, warning, error
    }

    struct PerformanceMetrics: Codable {
        let fps: Double
        let gpuTime: Double
        let cpuTime: Double
        let drawCalls: Int
    }

    struct MemoryMetrics: Codable {
        let used: Int64
        let available: Int64
        let textures: Int64
        let buffers: Int64
    }

    // MARK: - Buffering

    private var logBuffer: [LogEntry] = []
    private let maxLogBufferSize = 1000

    private var snapshotInterval: TimeInterval = 0.1  // 10 Hz
    private var lastSnapshotTime: TimeInterval = 0

    // MARK: - Network

    private var streamingURL: URL?
    private var urlSession: URLSession?

    // MARK: - Statistics

    private(set) var snapshotsSent: Int = 0
    private(set) var bytesSent: Int64 = 0
    private(set) var connectionErrors: Int = 0

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        urlSession = URLSession(configuration: config)

        print("✅ Remote Telemetry Manager initialized")
    }

    // MARK: - Connection

    /// Connect to remote telemetry endpoint
    func connect(to endpoint: String) async throws {
        guard let url = URL(string: endpoint) else {
            throw TelemetryError.invalidEndpoint
        }

        streamingURL = url
        remoteEndpoint = endpoint
        isConnected = true

        print("✅ Connected to telemetry endpoint: \(endpoint)")
    }

    /// Disconnect from remote endpoint
    func disconnect() {
        isConnected = false
        streamingURL = nil
        print("Disconnected from telemetry endpoint")
    }

    // MARK: - Logging

    /// Log message for telemetry
    func log(_ message: String, level: LogLevel = .info, category: String = "General") {
        guard isEnabled else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            category: category
        )

        logBuffer.append(entry)

        if logBuffer.count > maxLogBufferSize {
            logBuffer.removeFirst()
        }
    }

    // MARK: - Telemetry Capture

    /// Update telemetry (call from game loop)
    func update(deltaTime: TimeInterval, currentTime: TimeInterval) {
        guard isEnabled, isConnected else { return }

        if currentTime - lastSnapshotTime >= snapshotInterval {
            captureAndSendSnapshot()
            lastSnapshotTime = currentTime
        }
    }

    private func captureAndSendSnapshot() {
        let snapshot = TelemetrySnapshot(
            timestamp: Date(),
            transforms: captureTransforms(),
            logs: Array(logBuffer.suffix(100)),  // Last 100 logs
            performance: capturePerformance(),
            memory: captureMemory()
        )

        Task {
            await sendSnapshot(snapshot)
        }
    }

    private func captureTransforms() -> [TransformTelemetry] {
        // Capture entity transforms
        // In real implementation, would query all entities in scene
        return []
    }

    private func capturePerformance() -> PerformanceMetrics {
        return PerformanceMetrics(
            fps: 90.0,
            gpuTime: 8.0,
            cpuTime: 4.0,
            drawCalls: 1500
        )
    }

    private func captureMemory() -> MemoryMetrics {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let usedMemory = kerr == KERN_SUCCESS ? Int64(taskInfo.resident_size) : 0

        return MemoryMetrics(
            used: usedMemory,
            available: 16 * 1024 * 1024 * 1024,  // 16 GB (Vision Pro)
            textures: 0,
            buffers: 0
        )
    }

    private func sendSnapshot(_ snapshot: TelemetrySnapshot) async {
        guard let url = streamingURL, let session = urlSession else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                snapshotsSent += 1
                bytesSent += Int64(data.count)
            }
        } catch {
            connectionErrors += 1
            print("Telemetry send error: \(error)")
        }
    }

    // MARK: - Configuration

    func setSnapshotInterval(_ interval: TimeInterval) {
        snapshotInterval = interval
        print("Telemetry snapshot interval: \(String(format: "%.2f", interval))s (\(Int(1.0 / interval)) Hz)")
    }

    // MARK: - Statistics

    func getTelemetryStats() -> TelemetryStats {
        return TelemetryStats(
            isEnabled: isEnabled,
            isConnected: isConnected,
            endpoint: remoteEndpoint,
            snapshotsSent: snapshotsSent,
            bytesSent: bytesSent,
            connectionErrors: connectionErrors,
            logBufferSize: logBuffer.count
        )
    }

    func getDebugInfo() -> String {
        let stats = getTelemetryStats()

        var info = "=== Remote Telemetry ===\n"
        info += "Status: \(stats.isEnabled ? "Enabled" : "Disabled")\n"
        info += "Connected: \(stats.isConnected)\n"
        if let endpoint = stats.endpoint {
            info += "Endpoint: \(endpoint)\n"
        }
        info += "Snapshots Sent: \(stats.snapshotsSent)\n"
        info += "Data Sent: \(ByteCountFormatter.string(fromByteCount: stats.bytesSent, countStyle: .file))\n"
        info += "Errors: \(stats.connectionErrors)\n"
        info += "Log Buffer: \(stats.logBufferSize)\n"
        info += "====================="

        return info
    }
}

struct TelemetryStats {
    let isEnabled: Bool
    let isConnected: Bool
    let endpoint: String?
    let snapshotsSent: Int
    let bytesSent: Int64
    let connectionErrors: Int
    let logBufferSize: Int
}

enum TelemetryError: Error {
    case invalidEndpoint
    case connectionFailed
}
