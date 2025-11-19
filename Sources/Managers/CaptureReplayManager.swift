import Foundation
import ARKit
import simd

/// Captures and replays AR sessions for debugging without headset
@MainActor
class CaptureReplayManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isCapturing = false
    @Published var isReplaying = false
    @Published var replayProgress: Float = 0.0

    // MARK: - Capture Data

    struct CaptureSession: Codable {
        let id: UUID
        let startTime: Date
        let duration: TimeInterval
        let frames: [CapturedFrame]

        struct CapturedFrame: Codable {
            let frameNumber: Int
            let timestamp: TimeInterval
            let cameraTransform: Matrix4x4
            let anchors: [CapturedAnchor]
            let inputs: [CapturedInput]

            struct CapturedAnchor: Codable {
                let id: UUID
                let transform: Matrix4x4
                let type: String
            }

            struct CapturedInput: Codable {
                let type: String
                let data: Data
            }
        }
    }

    struct Matrix4x4: Codable {
        let columns: [[Float]]

        init(from transform: simd_float4x4) {
            columns = [
                [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w],
                [transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w],
                [transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w],
                [transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
            ]
        }

        func toSimd() -> simd_float4x4 {
            return simd_float4x4(
                SIMD4<Float>(columns[0][0], columns[0][1], columns[0][2], columns[0][3]),
                SIMD4<Float>(columns[1][0], columns[1][1], columns[1][2], columns[1][3]),
                SIMD4<Float>(columns[2][0], columns[2][1], columns[2][2], columns[2][3]),
                SIMD4<Float>(columns[3][0], columns[3][1], columns[3][2], columns[3][3])
            )
        }
    }

    // MARK: - Capture State

    private var currentSession: CaptureSession?
    private var capturedFrames: [CaptureSession.CapturedFrame] = []
    private var captureStartTime: Date?
    private var frameNumber: Int = 0

    // MARK: - Replay State

    private var replaySession: CaptureSession?
    private var currentReplayFrame: Int = 0
    private var replayStartTime: TimeInterval = 0

    // MARK: - Storage

    private let capturesDirectory: URL

    // MARK: - AR Integration

    private weak var arView: ARView?

    // MARK: - Statistics

    private(set) var capturesRecorded: Int = 0
    private(set) var replaysPlayed: Int = 0
    private(set) var totalFramesCaptured: Int = 0

    // MARK: - Initialization

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        capturesDirectory = documentsPath.appendingPathComponent("Captures")

        try? FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

        print("✅ Capture/Replay Manager initialized")
    }

    // MARK: - Setup

    func setup(arView: ARView) {
        self.arView = arView
        print("Capture/replay linked to ARView")
    }

    // MARK: - Capture

    /// Start capturing session
    func startCapture() {
        guard !isCapturing else { return }

        isCapturing = true
        capturedFrames.removeAll()
        captureStartTime = Date()
        frameNumber = 0

        print("Started session capture")
    }

    /// Stop capturing and save
    func stopCapture() async throws {
        guard isCapturing else { return }

        isCapturing = false

        guard let startTime = captureStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)

        let session = CaptureSession(
            id: UUID(),
            startTime: startTime,
            duration: duration,
            frames: capturedFrames
        )

        try await saveCapture(session)

        capturesRecorded += 1
        totalFramesCaptured += capturedFrames.count

        print("✅ Capture stopped: \(capturedFrames.count) frames, \(String(format: "%.2f", duration))s")
    }

    /// Capture current frame
    func captureFrame(from frame: ARFrame) {
        guard isCapturing else { return }

        let cameraTransform = Matrix4x4(from: frame.camera.transform)

        // Capture anchors
        var capturedAnchors: [CaptureSession.CapturedFrame.CapturedAnchor] = []
        for anchor in frame.anchors {
            let capturedAnchor = CaptureSession.CapturedFrame.CapturedAnchor(
                id: anchor.identifier,
                transform: Matrix4x4(from: anchor.transform),
                type: String(describing: type(of: anchor))
            )
            capturedAnchors.append(capturedAnchor)
        }

        let timestamp = frame.timestamp

        let capturedFrame = CaptureSession.CapturedFrame(
            frameNumber: frameNumber,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            anchors: capturedAnchors,
            inputs: []  // Would capture inputs
        )

        capturedFrames.append(capturedFrame)
        frameNumber += 1
    }

    // MARK: - Save/Load

    private func saveCapture(_ session: CaptureSession) async throws {
        let filename = "capture_\(session.id.uuidString).json"
        let fileURL = capturesDirectory.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        try data.write(to: fileURL)

        print("Saved capture: \(filename)")
    }

    /// Load capture from disk
    func loadCapture(id: UUID) async throws -> CaptureSession {
        let filename = "capture_\(id.uuidString).json"
        let fileURL = capturesDirectory.appendingPathComponent(filename)

        let data = try Data(contentsOf: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(CaptureSession.self, from: data)

        return session
    }

    /// Get all saved captures
    func getSavedCaptures() -> [CaptureSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: capturesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var sessions: [CaptureSession] = []

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let session = try decoder.decode(CaptureSession.self, from: data)
                sessions.append(session)
            } catch {
                print("Failed to load capture: \(error)")
            }
        }

        return sessions.sorted { $0.startTime > $1.startTime }
    }

    // MARK: - Replay

    /// Start replaying captured session
    func startReplay(session: CaptureSession) {
        guard !isReplaying else { return }

        replaySession = session
        currentReplayFrame = 0
        replayStartTime = CACurrentMediaTime()
        isReplaying = true

        print("Started replay: \(session.frames.count) frames")
    }

    /// Stop replay
    func stopReplay() {
        isReplaying = false
        replaySession = nil
        currentReplayFrame = 0
        replayProgress = 0

        print("Stopped replay")
    }

    /// Update replay (call from game loop)
    func updateReplay(currentTime: TimeInterval) {
        guard isReplaying, let session = replaySession else { return }

        let elapsedTime = currentTime - replayStartTime

        // Find frame to play
        while currentReplayFrame < session.frames.count {
            let frame = session.frames[currentReplayFrame]

            if frame.timestamp <= elapsedTime {
                playFrame(frame)
                currentReplayFrame += 1
                replayProgress = Float(currentReplayFrame) / Float(session.frames.count)
            } else {
                break
            }
        }

        // Check if replay finished
        if currentReplayFrame >= session.frames.count {
            stopReplay()
            replaysPlayed += 1
            print("Replay completed")
        }
    }

    private func playFrame(_ frame: CaptureSession.CapturedFrame) {
        // Apply captured camera transform
        // Restore anchors
        // Replay inputs

        // Post notification for debugging
        NotificationCenter.default.post(
            name: .replayFramePlayed,
            object: frame
        )
    }

    // MARK: - Statistics

    func getCaptureReplayStats() -> CaptureReplayStats {
        return CaptureReplayStats(
            isCapturing: isCapturing,
            isReplaying: isReplaying,
            capturesRecorded: capturesRecorded,
            replaysPlayed: replaysPlayed,
            totalFramesCaptured: totalFramesCaptured,
            currentCaptureFrames: capturedFrames.count,
            replayProgress: replayProgress,
            savedCaptures: getSavedCaptures().count
        )
    }

    func getDebugInfo() -> String {
        let stats = getCaptureReplayStats()

        var info = "=== Capture/Replay ===\n"
        info += "Capturing: \(stats.isCapturing)\n"
        info += "Replaying: \(stats.isReplaying)\n"
        info += "Captures Recorded: \(stats.capturesRecorded)\n"
        info += "Replays Played: \(stats.replaysPlayed)\n"
        info += "Total Frames: \(stats.totalFramesCaptured)\n"

        if stats.isCapturing {
            info += "Current Capture: \(stats.currentCaptureFrames) frames\n"
        }

        if stats.isReplaying {
            info += "Replay Progress: \(Int(stats.replayProgress * 100))%\n"
        }

        info += "Saved Captures: \(stats.savedCaptures)\n"
        info += "===================="

        return info
    }
}

struct CaptureReplayStats {
    let isCapturing: Bool
    let isReplaying: Bool
    let capturesRecorded: Int
    let replaysPlayed: Int
    let totalFramesCaptured: Int
    let currentCaptureFrames: Int
    let replayProgress: Float
    let savedCaptures: Int
}

extension Notification.Name {
    static let replayFramePlayed = Notification.Name("replayFramePlayed")
}
