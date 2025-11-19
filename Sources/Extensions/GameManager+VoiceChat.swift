import Foundation
import Combine
import ObjectiveC

extension GameManager {
    /// Voice chat manager
    var voiceChatManager: VoiceChatManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.voiceChatManager) as? VoiceChatManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.voiceChatManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Setup voice chat system
    func setupVoiceChat() {
        guard voiceChatManager == nil else { return }

        let manager = VoiceChatManager()
        voiceChatManager = manager

        // Hook up audio output to network
        manager.onAudioDataReady = { [weak self] audioData in
            self?.sendVoiceChat(audioData: audioData)
        }

        // Listen for incoming voice chat
        NotificationCenter.default.publisher(for: .voiceChatReceived)
            .sink { [weak self] notification in
                guard let participantID = notification.userInfo?["participantID"] as? UUID,
                      let audioData = notification.userInfo?["audioData"] as? Data else {
                    return
                }
                self?.handleReceivedVoiceChat(from: participantID, audioData: audioData)
            }
            .store(in: &cancellables)

        // Cleanup when players leave
        NotificationCenter.default.publisher(for: .remotePlayerLeft)
            .sink { [weak self] notification in
                guard let playerID = notification.userInfo?["playerID"] as? UUID else { return }
                self?.voiceChatManager?.removePlayer(for: playerID)
            }
            .store(in: &cancellables)

        print("Voice chat system initialized")
    }

    /// Start voice chat recording
    func startVoiceChat() async throws {
        guard let manager = voiceChatManager else {
            print("Voice chat not initialized")
            return
        }

        try await manager.startRecording()
        print("Voice chat recording started")
    }

    /// Stop voice chat recording
    func stopVoiceChat() {
        voiceChatManager?.stopRecording()
        print("Voice chat recording stopped")
    }

    /// Toggle mute
    func toggleVoiceMute() {
        voiceChatManager?.toggleMute()
    }

    /// Send voice chat audio to network
    private func sendVoiceChat(audioData: Data) {
        guard let localPlayer = localPlayer else { return }

        // Create voice chat message
        let message = NetworkMessage.voiceChat(
            participantID: localPlayer.id,
            audioData: audioData
        )

        // Post to network manager for transmission
        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )
    }

    /// Handle received voice chat audio
    private func handleReceivedVoiceChat(from participantID: UUID, audioData: Data) {
        voiceChatManager?.playRemoteAudio(from: participantID, audioData: audioData)
    }

    /// Get active speakers
    var activeSpeakers: Set<UUID> {
        return voiceChatManager?.activeSpeakers ?? []
    }

    /// Get local audio level
    var audioLevel: Float {
        return voiceChatManager?.audioLevel ?? 0.0
    }

    /// Check if recording
    var isRecordingVoice: Bool {
        return voiceChatManager?.isRecording ?? false
    }

    /// Check if muted
    var isVoiceMuted: Bool {
        return voiceChatManager?.isMuted ?? false
    }
}

// MARK: - Associated Keys

private extension AssociatedKeys {
    static var voiceChatManager = "voiceChatManager"
}

// MARK: - Network Integration

extension NetworkManager {
    /// Setup voice chat message forwarding
    func setupVoiceChatForwarding() {
        NotificationCenter.default.publisher(for: .sendNetworkMessage)
            .sink { [weak self] notification in
                guard let message = notification.userInfo?["message"] as? NetworkMessage else {
                    return
                }
                self?.sendMessage(message)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let sendNetworkMessage = Notification.Name("sendNetworkMessage")
}
