import Foundation
import simd

/// Deterministic simulation layer for multiplayer replay and rollback
@MainActor
class DeterministicSimulationManager {

    // MARK: - Simulation State

    struct SimulationState: Codable {
        let frame: UInt64
        let timestamp: TimeInterval
        let entities: [EntityState]
        let randomSeed: UInt64

        struct EntityState: Codable {
            let id: UUID
            let position: SIMD3<Float>
            let rotation: simd_quatf
            let velocity: SIMD3<Float>
        }
    }

    // MARK: - Configuration

    var fixedTimeStep: TimeInterval = 1.0 / 60.0  // 60 FPS
    var maxStoredStates: Int = 300  // 5 seconds at 60 FPS

    // MARK: - State History

    private var stateHistory: [UInt64: SimulationState] = [:]
    private var currentFrame: UInt64 = 0
    private var accumulator: TimeInterval = 0

    // MARK: - Random Number Generator

    private var randomSeed: UInt64
    private var rng: SeededRandomGenerator

    // MARK: - Statistics

    private(set) var framesSimulated: UInt64 = 0
    private(set) var rollbacksPerformed: Int = 0
    private(set) var statesStored: Int = 0

    // MARK: - Initialization

    init(seed: UInt64 = 0) {
        self.randomSeed = seed
        self.rng = SeededRandomGenerator(seed: seed)

        print("✅ Deterministic Simulation initialized (seed: \(seed))")
    }

    // MARK: - Simulation Step

    /// Update with variable delta time
    func update(deltaTime: TimeInterval) {
        accumulator += deltaTime

        // Fixed timestep simulation
        while accumulator >= fixedTimeStep {
            step()
            accumulator -= fixedTimeStep
        }
    }

    /// Perform one fixed timestep
    private func step() {
        // Capture current state
        let state = captureState()
        storeState(state)

        // Simulate frame
        currentFrame += 1
        framesSimulated += 1

        // Physics and game logic would run here with deterministic fixed timestep
    }

    private func captureState() -> SimulationState {
        // Capture all entity states
        // In production, would query all entities in scene

        return SimulationState(
            frame: currentFrame,
            timestamp: Double(currentFrame) * fixedTimeStep,
            entities: [],
            randomSeed: rng.currentSeed
        )
    }

    private func storeState(_ state: SimulationState) {
        stateHistory[state.frame] = state
        statesStored = stateHistory.count

        // Limit stored states
        if stateHistory.count > maxStoredStates {
            let oldestFrame = currentFrame - UInt64(maxStoredStates)
            stateHistory.removeValue(forKey: oldestFrame)
        }
    }

    // MARK: - Rollback

    /// Rollback to specific frame
    func rollback(to frame: UInt64) -> Bool {
        guard let state = stateHistory[frame] else {
            print("ERROR: Cannot rollback to frame \(frame) - state not found")
            return false
        }

        // Restore state
        restoreState(state)
        currentFrame = frame
        rollbacksPerformed += 1

        print("Rolled back to frame \(frame)")
        return true
    }

    /// Rollback by number of frames
    func rollback(frames: UInt64) -> Bool {
        let targetFrame = currentFrame > frames ? currentFrame - frames : 0
        return rollback(to: targetFrame)
    }

    private func restoreState(_ state: SimulationState) {
        // Restore entity states
        // In production, would apply to all entities

        // Restore RNG state
        rng.seed = state.randomSeed
    }

    // MARK: - Replay

    /// Replay from specific frame
    func startReplay(from frame: UInt64) -> Bool {
        return rollback(to: frame)
    }

    /// Get state at frame for replay
    func getState(at frame: UInt64) -> SimulationState? {
        return stateHistory[frame]
    }

    // MARK: - Netcode Support

    /// Predict future state for client-side prediction
    func predict(frames: Int, inputs: [Any]) -> SimulationState? {
        // Save current state
        let savedFrame = currentFrame
        let savedState = captureState()

        // Simulate forward
        for _ in 0..<frames {
            step()
        }

        let predictedState = captureState()

        // Restore
        restoreState(savedState)
        currentFrame = savedFrame

        return predictedState
    }

    /// Verify state matches (for anti-cheat)
    func verifyState(_ state: SimulationState) -> Bool {
        guard let localState = stateHistory[state.frame] else {
            return false
        }

        // Compare states (simplified)
        return localState.randomSeed == state.randomSeed
    }

    // MARK: - Deterministic Random

    /// Get deterministic random number
    func random() -> Float {
        return rng.nextFloat()
    }

    /// Get deterministic random in range
    func random(in range: ClosedRange<Float>) -> Float {
        let value = rng.nextFloat()
        return range.lowerBound + value * (range.upperBound - range.lowerBound)
    }

    // MARK: - Control

    /// Reset simulation
    func reset(seed: UInt64? = nil) {
        currentFrame = 0
        accumulator = 0
        stateHistory.removeAll()
        statesStored = 0

        if let seed = seed {
            randomSeed = seed
            rng.seed = seed
        }

        print("Simulation reset (seed: \(randomSeed))")
    }

    /// Set random seed
    func setRandomSeed(_ seed: UInt64) {
        randomSeed = seed
        rng.seed = seed
        print("Random seed set: \(seed)")
    }

    // MARK: - Statistics

    func getSimulationStats() -> SimulationStats {
        return SimulationStats(
            currentFrame: currentFrame,
            framesSimulated: framesSimulated,
            rollbacksPerformed: rollbacksPerformed,
            statesStored: statesStored,
            fixedTimeStep: fixedTimeStep,
            randomSeed: randomSeed
        )
    }

    func getDebugInfo() -> String {
        let stats = getSimulationStats()

        var info = "=== Deterministic Simulation ===\n"
        info += "Current Frame: \(stats.currentFrame)\n"
        info += "Frames Simulated: \(stats.framesSimulated)\n"
        info += "Rollbacks: \(stats.rollbacksPerformed)\n"
        info += "States Stored: \(stats.statesStored)/\(maxStoredStates)\n"
        info += "Fixed Timestep: \(String(format: "%.2f", stats.fixedTimeStep * 1000))ms\n"
        info += "Random Seed: \(stats.randomSeed)\n"
        info += "============================="

        return info
    }
}

// MARK: - Seeded Random Generator

struct SeededRandomGenerator {
    var seed: UInt64

    var currentSeed: UInt64 {
        return seed
    }

    mutating func nextUInt64() -> UInt64 {
        // xorshift64 algorithm (deterministic)
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return seed
    }

    mutating func nextFloat() -> Float {
        return Float(nextUInt64() & 0xFFFFFF) / Float(0xFFFFFF)
    }
}

struct SimulationStats {
    let currentFrame: UInt64
    let framesSimulated: UInt64
    let rollbacksPerformed: Int
    let statesStored: Int
    let fixedTimeStep: TimeInterval
    let randomSeed: UInt64
}
