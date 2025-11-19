import Foundation
import Combine
import ObjectiveC
import simd

extension GameManager {
    // MARK: - Associated Properties

    var proximityVoiceChatManager: ProximityVoiceChatManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.proximityVoiceChatManager) as? ProximityVoiceChatManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.proximityVoiceChatManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isProximityVoiceChatEnabled: Bool {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.isProximityVoiceChatEnabled) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.isProximityVoiceChatEnabled, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Setup

    /// Setup proximity voice chat (call after setupVoiceChat)
    func setupProximityVoiceChat(preset: ProximityVoiceChatManager.Preset = .normal) {
        guard let voiceChatManager = voiceChatManager else {
            print("ERROR: Must call setupVoiceChat() before setupProximityVoiceChat()")
            return
        }

        guard proximityVoiceChatManager == nil else {
            print("Proximity voice chat already initialized")
            return
        }

        // Create proximity voice chat manager
        let proximityManager = ProximityVoiceChatManager(voiceChatManager: voiceChatManager)
        proximityVoiceChatManager = proximityManager

        // Apply preset
        proximityManager.applyPreset(preset)

        // Start audio engine
        do {
            try proximityManager.start()
        } catch {
            print("Failed to start proximity voice chat: \(error)")
            return
        }

        // Replace voice chat audio callback with proximity version
        voiceChatManager.onAudioDataReady = { [weak self] audioData in
            self?.sendProximityVoiceChat(audioData: audioData)
        }

        // Listen for incoming proximity voice chat
        NotificationCenter.default.publisher(for: .proximityVoiceChatReceived)
            .sink { [weak self] notification in
                guard let participantID = notification.userInfo?["participantID"] as? UUID,
                      let audioData = notification.userInfo?["audioData"] as? Data,
                      let position = notification.userInfo?["position"] as? SIMD3<Float> else {
                    return
                }
                self?.handleReceivedProximityVoiceChat(from: participantID, audioData: audioData, position: position)
            }
            .store(in: &cancellables)

        // Update player positions automatically
        setupPlayerPositionTracking()

        // Cleanup when players leave
        NotificationCenter.default.publisher(for: .remotePlayerLeft)
            .sink { [weak self] notification in
                guard let playerID = notification.userInfo?["playerID"] as? UUID else { return }
                self?.proximityVoiceChatManager?.removePlayer(playerID)
            }
            .store(in: &cancellables)

        isProximityVoiceChatEnabled = true
        print("✅ Proximity voice chat initialized with preset: \(preset)")
    }

    /// Setup automatic player position tracking for proximity voice chat
    private func setupPlayerPositionTracking() {
        // Track local player position updates
        NotificationCenter.default.publisher(for: .localPlayerPositionUpdated)
            .sink { [weak self] notification in
                guard let position = notification.userInfo?["position"] as? SIMD3<Float>,
                      let forward = notification.userInfo?["forward"] as? SIMD3<Float> else {
                    return
                }
                self?.proximityVoiceChatManager?.updateLocalPlayerPosition(position, forward: forward)
            }
            .store(in: &cancellables)

        // Track remote player position updates
        NotificationCenter.default.publisher(for: .remotePlayerPositionUpdated)
            .sink { [weak self] notification in
                guard let playerID = notification.userInfo?["playerID"] as? UUID,
                      let position = notification.userInfo?["position"] as? SIMD3<Float> else {
                    return
                }
                self?.proximityVoiceChatManager?.updatePlayerPosition(playerID, position: position)
            }
            .store(in: &cancellables)

        print("Player position tracking for proximity voice chat enabled")
    }

    // MARK: - Voice Chat Control

    /// Start voice chat with proximity (replaces startVoiceChat)
    func startProximityVoiceChat() async throws {
        guard isProximityVoiceChatEnabled else {
            // Fall back to regular voice chat
            try await startVoiceChat()
            return
        }

        try await voiceChatManager?.startRecording()
        print("Proximity voice chat recording started")
    }

    /// Stop proximity voice chat
    func stopProximityVoiceChat() {
        voiceChatManager?.stopRecording()
        print("Proximity voice chat recording stopped")
    }

    // MARK: - Network Integration

    /// Send voice chat with position data
    private func sendProximityVoiceChat(audioData: Data) {
        guard let localPlayer = localPlayer else { return }
        guard isProximityVoiceChatEnabled else {
            // Fall back to regular voice chat
            sendVoiceChat(audioData: audioData)
            return
        }

        // Create proximity voice chat message with position
        let message = NetworkMessage.proximityVoiceChat(
            participantID: localPlayer.id,
            audioData: audioData,
            position: localPlayer.position
        )

        // Post to network manager for transmission
        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )
    }

    /// Handle received proximity voice chat
    private func handleReceivedProximityVoiceChat(from participantID: UUID, audioData: Data, position: SIMD3<Float>) {
        guard isProximityVoiceChatEnabled,
              let proximityManager = proximityVoiceChatManager else {
            // Fall back to regular voice chat
            voiceChatManager?.playRemoteAudio(from: participantID, audioData: audioData)
            return
        }

        // Play with spatial positioning
        proximityManager.playRemoteAudio(from: participantID, audioData: audioData, position: position)

        // Update player position in game state
        if let player = remotePlayers[participantID] {
            player.position = position
            player.updateEntityTransform()
        }
    }

    // MARK: - Position Updates

    /// Update local player position (call from game loop)
    func updateLocalPlayerPositionForVoiceChat() {
        guard let localPlayer = localPlayer,
              isProximityVoiceChatEnabled else { return }

        // Calculate forward vector from rotation
        let forward = localPlayer.rotation.act(SIMD3<Float>(0, 0, -1))

        // Update proximity voice chat
        proximityVoiceChatManager?.updateLocalPlayerPosition(localPlayer.position, forward: forward)

        // Notify other systems
        NotificationCenter.default.post(
            name: .localPlayerPositionUpdated,
            object: nil,
            userInfo: [
                "position": localPlayer.position,
                "forward": forward
            ]
        )
    }

    /// Update remote player position
    func updateRemotePlayerPosition(_ playerID: UUID, position: SIMD3<Float>) {
        // Update player model
        if let player = remotePlayers[playerID] {
            player.position = position
            player.updateEntityTransform()
        }

        // Update proximity voice chat
        if isProximityVoiceChatEnabled {
            proximityVoiceChatManager?.updatePlayerPosition(playerID, position: position)
        }

        // Notify other systems
        NotificationCenter.default.post(
            name: .remotePlayerPositionUpdated,
            object: nil,
            userInfo: [
                "playerID": playerID,
                "position": position
            ]
        )
    }

    // MARK: - Configuration

    /// Change proximity voice chat preset
    func setProximityVoiceChatPreset(_ preset: ProximityVoiceChatManager.Preset) {
        proximityVoiceChatManager?.applyPreset(preset)
        print("Applied proximity voice chat preset: \(preset)")
    }

    /// Set custom attenuation parameters
    func setProximityVoiceChatAttenuation(maxDistance: Float, referenceDistance: Float, rolloff: Float = 1.0) {
        proximityVoiceChatManager?.updateAttenuationParameters(
            maxDistance: maxDistance,
            referenceDistance: referenceDistance,
            rolloff: rolloff
        )
    }

    /// Toggle proximity voice chat on/off
    func toggleProximityVoiceChat() {
        guard let proximityManager = proximityVoiceChatManager else { return }
        proximityManager.isEnabled.toggle()
        print("Proximity voice chat: \(proximityManager.isEnabled ? "enabled" : "disabled")")
    }

    // MARK: - Queries

    /// Get all players within hearing distance
    func getPlayersInVoiceRange() -> [(UUID, Float)] {
        guard let proximityManager = proximityVoiceChatManager else { return [] }
        return proximityManager.getPlayersInRange().map { ($0.0, $0.2) }
    }

    /// Check if can hear specific player
    func canHearPlayer(_ playerID: UUID) -> Bool {
        return proximityVoiceChatManager?.canHearPlayer(playerID) ?? false
    }

    /// Get distance to player
    func distanceToPlayer(_ playerID: UUID) -> Float? {
        return proximityVoiceChatManager?.distanceToPlayer(playerID)
    }

    /// Get volume level for player's voice
    func voiceVolumeForPlayer(_ playerID: UUID) -> Float {
        return proximityVoiceChatManager?.volumeForPlayer(playerID) ?? 0.0
    }

    // MARK: - Debug

    /// Print proximity voice chat debug info
    func printProximityVoiceChatDebug() {
        proximityVoiceChatManager?.printDebugInfo()
    }
}

// MARK: - Associated Keys Extension

private extension AssociatedKeys {
    static var proximityVoiceChatManager = "proximityVoiceChatManager"
    static var isProximityVoiceChatEnabled = "isProximityVoiceChatEnabled"
}

// MARK: - Network Message Extension

extension NetworkMessage {
    /// Proximity voice chat message with position data
    static func proximityVoiceChat(participantID: UUID, audioData: Data, position: SIMD3<Float>) -> NetworkMessage {
        let positionData = ProximityVoiceChatData(
            participantID: participantID,
            audioData: audioData,
            position: position
        )

        guard let encoded = try? JSONEncoder().encode(positionData) else {
            print("ERROR: Failed to encode proximity voice chat data")
            return .voiceChat(participantID: participantID, audioData: audioData)
        }

        return .gameEvent(encoded)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let localPlayerPositionUpdated = Notification.Name("localPlayerPositionUpdated")
    static let remotePlayerPositionUpdated = Notification.Name("remotePlayerPositionUpdated")
}
