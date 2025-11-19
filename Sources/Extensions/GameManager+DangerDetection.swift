import Foundation
import Combine
import ObjectiveC
import RealityKit
import simd

extension GameManager {
    // MARK: - Associated Properties

    var dangerDetectionManager: DangerousAreaDetectionManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.dangerDetectionManager) as? DangerousAreaDetectionManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.dangerDetectionManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isDangerDetectionEnabled: Bool {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.isDangerDetectionEnabled) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.isDangerDetectionEnabled, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Setup

    /// Setup dangerous area detection
    func setupDangerDetection(arView: RealityKit.ARView, sensitivity: DetectionSensitivity = .normal) {
        guard dangerDetectionManager == nil else {
            print("Danger detection already initialized")
            return
        }

        let manager = DangerousAreaDetectionManager()
        dangerDetectionManager = manager

        // Configure
        manager.detectionSensitivity = sensitivity
        manager.setup(arView: arView)

        // Setup notifications
        setupDangerDetectionNotifications()

        isDangerDetectionEnabled = true
        print("✅ Dangerous area detection initialized with \(sensitivity) sensitivity")
    }

    private func setupDangerDetectionNotifications() {
        // Listen for detected hazards
        NotificationCenter.default.publisher(for: .dangerousAreasDetected)
            .sink { [weak self] notification in
                guard let hazards = notification.userInfo?["hazards"] as? [DangerousArea],
                      let count = notification.userInfo?["count"] as? Int else {
                    return
                }
                self?.handleDetectedHazards(hazards, count: count)
            }
            .store(in: &cancellables)

        // Listen for danger level changes
        NotificationCenter.default.publisher(for: .dangerLevelChanged)
            .sink { [weak self] notification in
                guard let level = notification.userInfo?["level"] as? DangerLevel,
                      let distance = notification.userInfo?["closestDistance"] as? Float else {
                    return
                }
                self?.handleDangerLevelChanged(level, closestDistance: distance)
            }
            .store(in: &cancellables)

        print("Danger detection notifications configured")
    }

    // MARK: - Control

    /// Start danger detection
    func startDangerDetection() {
        guard let manager = dangerDetectionManager else {
            print("ERROR: Danger detection not initialized. Call setupDangerDetection() first")
            return
        }

        manager.startDetection()
        print("Danger detection started")
    }

    /// Stop danger detection
    func stopDangerDetection() {
        dangerDetectionManager?.stopDetection()
        print("Danger detection stopped")
    }

    /// Toggle danger detection
    func toggleDangerDetection() {
        guard let manager = dangerDetectionManager else { return }

        if manager.isActive {
            stopDangerDetection()
        } else {
            startDangerDetection()
        }
    }

    // MARK: - Update Loop Integration

    /// Update danger detection (call from game loop)
    func updateDangerDetection(deltaTime: TimeInterval) {
        guard let manager = dangerDetectionManager,
              let player = localPlayer,
              manager.isActive else {
            return
        }

        // Update danger detection with current player position
        manager.update(playerPosition: player.position, deltaTime: deltaTime)
    }

    // MARK: - Event Handlers

    private func handleDetectedHazards(_ hazards: [DangerousArea], count: Int) {
        print("⚠️ Detected \(count) hazard(s)")

        // Log critical hazards
        let criticalHazards = hazards.filter { $0.severity == .critical }
        if !criticalHazards.isEmpty {
            print("🚨 CRITICAL: \(criticalHazards.count) critical hazard(s) detected")
            for hazard in criticalHazards {
                print("   - \(hazard.type.rawValue) at \(hazard.position)")
            }
        }

        // Check if player is in danger
        if let player = localPlayer {
            let inDanger = dangerDetectionManager?.isPlayerInDanger(position: player.position) ?? false
            if inDanger {
                NotificationCenter.default.post(name: .playerEnteredDangerZone, object: nil)
            }
        }
    }

    private func handleDangerLevelChanged(_ level: DangerLevel, closestDistance: Float) {
        print("Danger level: \(level.rawValue) (closest: \(String(format: "%.1f", closestDistance))m)")

        // Can be used to trigger warnings, restrict movement, etc.
        if level == .critical || level == .high {
            print("⚠️ WARNING: High danger level detected!")
        }
    }

    // MARK: - Movement Safety

    /// Check if player can safely move in direction
    func canSafelyMove(direction: SIMD3<Float>) -> Bool {
        guard let player = localPlayer,
              let manager = dangerDetectionManager,
              manager.isActive else {
            return true  // Allow movement if detection disabled
        }

        let testPosition = player.position + direction * 0.5
        return manager.isSafePosition(testPosition)
    }

    /// Get safe direction to move (redirects around hazards)
    func getSafeMovementDirection(desiredDirection: SIMD3<Float>) -> SIMD3<Float>? {
        guard let player = localPlayer,
              let manager = dangerDetectionManager,
              manager.isActive else {
            return desiredDirection  // Return original if detection disabled
        }

        return manager.getSafeDirection(from: player.position, desiredDirection: desiredDirection)
    }

    /// Restrict player movement if near hazard
    func enforceMovementSafety(velocity: inout SIMD3<Float>) {
        guard let player = localPlayer,
              let manager = dangerDetectionManager,
              manager.isActive else {
            return
        }

        let proposedPosition = player.position + velocity * 0.1
        if !manager.isSafePosition(proposedPosition) {
            // Stop movement toward hazard
            if let safeDirection = manager.getSafeDirection(from: player.position, desiredDirection: velocity) {
                velocity = safeDirection * simd_length(velocity)
                print("⚠️ Movement redirected to avoid hazard")
            } else {
                velocity = SIMD3<Float>.zero
                print("🛑 Movement blocked - no safe direction")
            }
        }
    }

    // MARK: - Query Methods

    /// Get all currently detected hazards
    func getDetectedHazards() -> [DangerousArea] {
        return dangerDetectionManager?.detectedHazards ?? []
    }

    /// Get hazards near player
    func getHazardsNearPlayer(range: Float = 10.0) -> [DangerousArea] {
        guard let player = localPlayer,
              let manager = dangerDetectionManager else {
            return []
        }

        return manager.getHazardsNear(position: player.position, range: range)
    }

    /// Get closest hazard to player
    func getClosestHazardToPlayer() -> DangerousArea? {
        guard let player = localPlayer,
              let manager = dangerDetectionManager else {
            return nil
        }

        return manager.getClosestHazard(to: player.position)
    }

    /// Get hazards of specific type
    func getHazardsOfType(_ type: HazardType) -> [DangerousArea] {
        return dangerDetectionManager?.getHazardsOfType(type) ?? []
    }

    /// Check if player is currently in danger
    func isPlayerInDanger(threshold: Float = 2.0) -> Bool {
        guard let player = localPlayer,
              let manager = dangerDetectionManager else {
            return false
        }

        return manager.isPlayerInDanger(position: player.position, threshold: threshold)
    }

    /// Get current danger level
    var currentDangerLevel: DangerLevel {
        return dangerDetectionManager?.currentDangerLevel ?? .safe
    }

    // MARK: - Configuration

    /// Set detection sensitivity
    func setDangerDetectionSensitivity(_ sensitivity: DetectionSensitivity) {
        dangerDetectionManager?.detectionSensitivity = sensitivity
        print("Danger detection sensitivity: \(sensitivity.rawValue)")
    }

    /// Set safety margin around hazards
    func setSafetyMargin(_ margin: Float) {
        dangerDetectionManager?.safetyMargin = margin
        print("Safety margin set to \(margin)m")
    }

    /// Configure detection thresholds
    func configureDangerDetection(
        minimumDropHeight: Float? = nil,
        maximumSafeSlope: Float? = nil,
        waterDetectionDepth: Float? = nil
    ) {
        guard let manager = dangerDetectionManager else { return }

        if let dropHeight = minimumDropHeight {
            manager.minimumDropHeight = dropHeight
        }
        if let slope = maximumSafeSlope {
            manager.maximumSafeSlope = slope
        }
        if let waterDepth = waterDetectionDepth {
            manager.waterDetectionDepth = waterDepth
        }

        print("Danger detection thresholds updated")
    }

    // MARK: - Statistics

    /// Get danger detection statistics
    func getDangerDetectionStats() -> DangerDetectionStats {
        guard let manager = dangerDetectionManager else {
            return DangerDetectionStats(
                isActive: false,
                totalHazards: 0,
                hazardsByType: [:],
                hazardsBySeverity: [:],
                currentDangerLevel: .safe
            )
        }

        let hazards = manager.detectedHazards

        var byType: [HazardType: Int] = [:]
        var bySeverity: [DangerSeverity: Int] = [:]

        for hazard in hazards {
            byType[hazard.type, default: 0] += 1
            bySeverity[hazard.severity, default: 0] += 1
        }

        return DangerDetectionStats(
            isActive: manager.isActive,
            totalHazards: hazards.count,
            hazardsByType: byType,
            hazardsBySeverity: bySeverity,
            currentDangerLevel: manager.currentDangerLevel
        )
    }

    // MARK: - Debug

    /// Print danger detection debug info
    func printDangerDetectionDebug() {
        if let manager = dangerDetectionManager {
            print(manager.getDebugInfo())
        } else {
            print("Danger detection not initialized")
        }
    }

    /// Get hazard summary string
    func getHazardSummary() -> String {
        let stats = getDangerDetectionStats()

        var summary = "Hazards: \(stats.totalHazards)\n"

        if !stats.hazardsByType.isEmpty {
            summary += "By Type:\n"
            for (type, count) in stats.hazardsByType.sorted(by: { $0.value > $1.value }) {
                summary += "  • \(type.rawValue): \(count)\n"
            }
        }

        if !stats.hazardsBySeverity.isEmpty {
            summary += "By Severity:\n"
            for (severity, count) in stats.hazardsBySeverity.sorted(by: { $0.key > $1.key }) {
                summary += "  • \(severity.rawValue): \(count)\n"
            }
        }

        summary += "Danger Level: \(stats.currentDangerLevel.rawValue)"

        return summary
    }
}

// MARK: - Associated Keys Extension

private extension AssociatedKeys {
    static var dangerDetectionManager = "dangerDetectionManager"
    static var isDangerDetectionEnabled = "isDangerDetectionEnabled"
}

// MARK: - Statistics Structure

struct DangerDetectionStats {
    let isActive: Bool
    let totalHazards: Int
    let hazardsByType: [HazardType: Int]
    let hazardsBySeverity: [DangerSeverity: Int]
    let currentDangerLevel: DangerLevel
}
