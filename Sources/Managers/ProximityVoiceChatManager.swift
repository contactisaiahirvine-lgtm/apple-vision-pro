import Foundation
import AVFoundation
import Combine
import simd

/// Manages proximity-based voice chat with 3D spatial audio positioning
/// Remote players' voices are positioned in 3D space based on their location
/// Volume automatically attenuates with distance
@MainActor
class ProximityVoiceChatManager: ObservableObject {
    @Published var isEnabled = true
    @Published var maxHearingDistance: Float = 50.0  // meters
    @Published var referenceDistance: Float = 1.0     // distance for full volume
    @Published var spatialBlend: Float = 1.0           // 0.0 = 2D, 1.0 = full 3D

    // Core voice chat manager
    private let voiceChatManager: VoiceChatManager

    // Audio environment for 3D positioning
    private var audioEnvironment: AVAudioEnvironmentNode?
    private var audioEngine: AVAudioEngine?

    // Player positions (updated from network)
    private var playerPositions: [UUID: SIMD3<Float>] = [:]
    private var localPlayerPosition: SIMD3<Float> = .zero

    // Spatial audio players for each remote participant
    private var spatialPlayers: [UUID: SpatialVoicePlayer] = [:]

    // Configuration
    private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)

    // Attenuation model
    enum AttenuationModel {
        case linear
        case inverse       // Realistic physics-based
        case exponential
        case logarithmic
    }
    var attenuationModel: AttenuationModel = .inverse

    init(voiceChatManager: VoiceChatManager) {
        self.voiceChatManager = voiceChatManager
        setupSpatialAudio()
    }

    // MARK: - Spatial Audio Setup

    private func setupSpatialAudio() {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else {
            print("Failed to create audio engine for proximity voice chat")
            return
        }

        // Create 3D audio environment
        audioEnvironment = AVAudioEnvironmentNode()

        guard let environment = audioEnvironment else { return }

        // Attach environment to engine
        engine.attach(environment)

        // Connect environment to main mixer
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        // Configure environment for realistic spatial audio
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = Float(referenceDistance)
        environment.distanceAttenuationParameters.maximumDistance = Float(maxHearingDistance)
        environment.distanceAttenuationParameters.rolloffFactor = 1.0

        // Configure reverb for spatial realism
        environment.reverbParameters.enable = true
        environment.reverbParameters.level = 0.3  // Subtle reverb

        // Set listener at origin initially
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0, pitch: 0, roll: 0
        )

        print("Proximity voice chat spatial audio initialized")
    }

    // MARK: - Position Updates

    /// Update local player position (listener position)
    func updateLocalPlayerPosition(_ position: SIMD3<Float>, forward: SIMD3<Float> = SIMD3(0, 0, -1)) {
        localPlayerPosition = position

        guard let environment = audioEnvironment else { return }

        // Update listener position
        environment.listenerPosition = AVAudio3DPoint(
            x: position.x,
            y: position.y,
            z: position.z
        )

        // Calculate orientation from forward vector
        let yaw = atan2(forward.x, forward.z)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: Float(yaw * 180.0 / .pi),
            pitch: 0,
            roll: 0
        )
    }

    /// Update remote player position
    func updatePlayerPosition(_ playerID: UUID, position: SIMD3<Float>) {
        playerPositions[playerID] = position

        // Update spatial player position if exists
        if let spatialPlayer = spatialPlayers[playerID] {
            spatialPlayer.updatePosition(position)
        }
    }

    /// Remove player from proximity tracking
    func removePlayer(_ playerID: UUID) {
        playerPositions.removeValue(forKey: playerID)

        if let spatialPlayer = spatialPlayers[playerID] {
            spatialPlayer.cleanup()
            spatialPlayers.removeValue(forKey: playerID)
        }
    }

    // MARK: - Audio Playback

    /// Play remote audio with spatial positioning
    func playRemoteAudio(from participantID: UUID, audioData: Data, position: SIMD3<Float>) {
        guard isEnabled else { return }

        // Update player position
        updatePlayerPosition(participantID, position: position)

        // Check if player is within hearing distance
        let distance = simd_distance(localPlayerPosition, position)
        guard distance <= maxHearingDistance else {
            // Too far away, don't play
            return
        }

        // Get or create spatial player
        let spatialPlayer = getOrCreateSpatialPlayer(for: participantID, at: position)

        // Decode audio
        let converter = AudioConverter()
        guard let buffer = converter.decode(data: audioData) else {
            print("Failed to decode audio for spatial playback")
            return
        }

        // Play with spatial positioning
        spatialPlayer.playBuffer(buffer)
    }

    private func getOrCreateSpatialPlayer(for participantID: UUID, at position: SIMD3<Float>) -> SpatialVoicePlayer {
        if let existing = spatialPlayers[participantID] {
            return existing
        }

        // Create new spatial player
        guard let engine = audioEngine,
              let environment = audioEnvironment,
              let format = audioFormat else {
            fatalError("Audio engine not properly initialized")
        }

        let player = SpatialVoicePlayer(
            participantID: participantID,
            engine: engine,
            environment: environment,
            format: format
        )

        player.updatePosition(position)
        spatialPlayers[participantID] = player

        print("Created spatial voice player for participant: \(participantID) at distance: \(simd_distance(localPlayerPosition, position))m")

        return player
    }

    // MARK: - Configuration

    /// Update attenuation parameters
    func updateAttenuationParameters(maxDistance: Float, referenceDistance: Float, rolloff: Float = 1.0) {
        self.maxHearingDistance = maxDistance
        self.referenceDistance = referenceDistance

        guard let environment = audioEnvironment else { return }

        environment.distanceAttenuationParameters.maximumDistance = maxDistance
        environment.distanceAttenuationParameters.referenceDistance = referenceDistance
        environment.distanceAttenuationParameters.rolloffFactor = rolloff

        print("Updated attenuation: max=\(maxDistance)m, ref=\(referenceDistance)m, rolloff=\(rolloff)")
    }

    /// Calculate volume for a given distance (for UI/debugging)
    func calculateVolume(for distance: Float) -> Float {
        guard distance <= maxHearingDistance else { return 0.0 }

        if distance <= referenceDistance {
            return 1.0
        }

        switch attenuationModel {
        case .linear:
            let attenuation = 1.0 - (distance - referenceDistance) / (maxHearingDistance - referenceDistance)
            return max(0.0, attenuation)

        case .inverse:
            // Realistic inverse distance law
            return referenceDistance / distance

        case .exponential:
            let normalizedDist = (distance - referenceDistance) / (maxHearingDistance - referenceDistance)
            return exp(-2.0 * normalizedDist)

        case .logarithmic:
            let ratio = distance / referenceDistance
            return 1.0 / (1.0 + log10(ratio))
        }
    }

    /// Get all players within hearing distance
    func getPlayersInRange() -> [(UUID, SIMD3<Float>, Float)] {
        return playerPositions.compactMap { (id, position) in
            let distance = simd_distance(localPlayerPosition, position)
            if distance <= maxHearingDistance {
                return (id, position, distance)
            }
            return nil
        }.sorted { $0.2 < $1.2 }  // Sort by distance
    }

    /// Start the audio engine
    func start() throws {
        guard let engine = audioEngine else {
            throw ProximityVoiceChatError.audioEngineNotInitialized
        }

        if !engine.isRunning {
            try engine.start()
            print("Proximity voice chat audio engine started")
        }
    }

    /// Stop the audio engine
    func stop() {
        audioEngine?.stop()
        print("Proximity voice chat audio engine stopped")
    }

    // MARK: - Cleanup

    func cleanup() {
        stop()

        for (_, player) in spatialPlayers {
            player.cleanup()
        }
        spatialPlayers.removeAll()
        playerPositions.removeAll()

        audioEnvironment = nil
        audioEngine = nil
    }

    deinit {
        cleanup()
    }
}

// MARK: - Spatial Voice Player

/// Manages a single spatial audio player for one remote participant
class SpatialVoicePlayer {
    let participantID: UUID
    private let playerNode: AVAudioPlayerNode
    private weak var environment: AVAudioEnvironmentNode?
    private let format: AVAudioFormat?

    init(participantID: UUID, engine: AVAudioEngine, environment: AVAudioEnvironmentNode, format: AVAudioFormat) {
        self.participantID = participantID
        self.playerNode = AVAudioPlayerNode()
        self.environment = environment
        self.format = format

        // Attach player to engine
        engine.attach(playerNode)

        // Connect player to 3D environment
        engine.connect(playerNode, to: environment, format: format)

        // Start playing
        playerNode.play()
    }

    /// Update the 3D position of this voice source
    func updatePosition(_ position: SIMD3<Float>) {
        guard let environment = environment else { return }

        // Set position in 3D space
        playerNode.position = AVAudio3DPoint(
            x: position.x,
            y: position.y,
            z: position.z
        )

        // Optional: Set render algorithm for best quality
        playerNode.renderingAlgorithm = .HRTF
    }

    /// Play an audio buffer
    func playBuffer(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer) {
            // Buffer completed
        }
    }

    /// Stop and cleanup
    func cleanup() {
        playerNode.stop()
        // Note: Engine will detach when player is deallocated
    }
}

// MARK: - Extensions for Convenience

extension ProximityVoiceChatManager {
    /// Get distance to a specific player
    func distanceToPlayer(_ playerID: UUID) -> Float? {
        guard let position = playerPositions[playerID] else { return nil }
        return simd_distance(localPlayerPosition, position)
    }

    /// Check if player is within hearing range
    func canHearPlayer(_ playerID: UUID) -> Bool {
        guard let distance = distanceToPlayer(playerID) else { return false }
        return distance <= maxHearingDistance
    }

    /// Get formatted distance string
    func distanceString(to playerID: UUID) -> String {
        guard let distance = distanceToPlayer(playerID) else { return "Unknown" }
        return String(format: "%.1fm", distance)
    }

    /// Get volume level for player (0.0 to 1.0)
    func volumeForPlayer(_ playerID: UUID) -> Float {
        guard let distance = distanceToPlayer(playerID) else { return 0.0 }
        return calculateVolume(for: distance)
    }
}

// MARK: - Errors

enum ProximityVoiceChatError: Error {
    case audioEngineNotInitialized
    case playerNotFound
    case positionNotAvailable
}

// MARK: - Notifications

extension Notification.Name {
    static let proximityVoiceChatPlayerInRange = Notification.Name("proximityVoiceChatPlayerInRange")
    static let proximityVoiceChatPlayerOutOfRange = Notification.Name("proximityVoiceChatPlayerOutOfRange")
}

// MARK: - Configuration Presets

extension ProximityVoiceChatManager {
    /// Preset configurations for different game scenarios
    enum Preset {
        case closeRange    // 10m max, good for small rooms
        case normal        // 50m max, default
        case longRange     // 100m max, open world
        case whispering    // 5m max, stealth games

        var maxDistance: Float {
            switch self {
            case .closeRange: return 10.0
            case .normal: return 50.0
            case .longRange: return 100.0
            case .whispering: return 5.0
            }
        }

        var referenceDistance: Float {
            switch self {
            case .closeRange: return 0.5
            case .normal: return 1.0
            case .longRange: return 2.0
            case .whispering: return 0.3
            }
        }
    }

    /// Apply a preset configuration
    func applyPreset(_ preset: Preset) {
        updateAttenuationParameters(
            maxDistance: preset.maxDistance,
            referenceDistance: preset.referenceDistance
        )
    }
}

// MARK: - Debug Utilities

extension ProximityVoiceChatManager {
    /// Get debug info about all active spatial players
    func getDebugInfo() -> String {
        var info = "=== Proximity Voice Chat Debug ===\n"
        info += "Enabled: \(isEnabled)\n"
        info += "Max Distance: \(maxHearingDistance)m\n"
        info += "Reference Distance: \(referenceDistance)m\n"
        info += "Attenuation Model: \(attenuationModel)\n"
        info += "Local Position: \(localPlayerPosition)\n"
        info += "\nActive Players: \(spatialPlayers.count)\n"

        for (id, position) in playerPositions {
            let distance = simd_distance(localPlayerPosition, position)
            let volume = calculateVolume(for: distance)
            let inRange = distance <= maxHearingDistance
            info += "  Player \(id): \(distance)m, vol=\(volume), \(inRange ? "IN RANGE" : "OUT OF RANGE")\n"
        }

        info += "================================"
        return info
    }

    /// Print debug info to console
    func printDebugInfo() {
        print(getDebugInfo())
    }
}
