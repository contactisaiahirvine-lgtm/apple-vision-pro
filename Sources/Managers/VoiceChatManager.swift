import Foundation
import AVFoundation
import Combine

/// Manages voice chat audio recording, streaming, and playback for multiplayer
@MainActor
class VoiceChatManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isMuted = false
    @Published var activeSpeakers: Set<UUID> = []
    @Published var audioLevel: Float = 0.0

    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)

    // Audio players for remote participants
    private var audioPlayers: [UUID: AVAudioPlayerNode] = [:]
    private var playerBufferQueues: [UUID: [AVAudioPCMBuffer]] = [:]

    // Audio session
    private let audioSession = AVAudioSession.sharedInstance()

    // Encoding/decoding
    private let audioConverter = AudioConverter()

    // Configuration
    private let bufferSize: AVAudioFrameCount = 1024
    private let audioQuality: Float = 0.5 // 0.0 to 1.0 (lower = more compression)

    // Network callback
    var onAudioDataReady: ((Data) -> Void)?

    override init() {
        super.init()
        setupAudioEngine()
    }

    // MARK: - Audio Session Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine,
              let format = audioFormat else {
            print("Failed to initialize audio engine")
            return
        }

        inputNode = engine.inputNode

        print("Audio engine initialized")
    }

    func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            print("Microphone permission denied")
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        // Request permission first
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            throw VoiceChatError.permissionDenied
        }

        guard let engine = audioEngine,
              let input = inputNode,
              let format = audioFormat else {
            throw VoiceChatError.audioEngineNotInitialized
        }

        // Configure audio session for recording
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        // Install tap on input node to capture audio
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }

        // Start the audio engine
        try engine.start()

        isRecording = true
        print("Voice chat recording started")
    }

    func stopRecording() {
        guard let engine = audioEngine,
              let input = inputNode else {
            return
        }

        // Remove tap and stop engine
        input.removeTap(onBus: 0)
        engine.stop()

        // Deactivate audio session
        try? audioSession.setActive(false)

        isRecording = false
        audioLevel = 0.0
        print("Voice chat recording stopped")
    }

    func toggleMute() {
        isMuted.toggle()
        print("Voice chat muted: \(isMuted)")
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // SAFETY: This function is called from the audio engine's real-time thread.
        // We must not access @MainActor properties directly from here.

        // Encode audio data (pure computation, thread-safe)
        guard let audioData = audioConverter.encode(buffer: buffer, quality: audioQuality) else {
            return
        }

        // Calculate audio level data (pure computation, thread-safe)
        let levelData = calculateAudioLevelData(from: buffer)

        // Dispatch to main actor to access properties and invoke callback
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Now safely check mute status on main actor
            guard !self.isMuted else { return }

            // Update audio level for UI
            self.audioLevel = levelData

            // Invoke callback (now on main thread)
            self.onAudioDataReady?(audioData)
        }
    }

    private func calculateAudioLevelData(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let channelDataValue = channelData.pointee
        // FIX: Simple iteration for non-interleaved mono format (removed invalid buffer.stride)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        var sumOfSquares: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sumOfSquares += sample * sample
        }

        let rms = sqrt(sumOfSquares / Float(frameLength))

        // SAFETY: Guard against log10(0) or log10(negative) to prevent -Infinity/NaN
        let avgPower: Float
        if rms > 0.0001 {  // Small threshold to avoid log10(0)
            avgPower = 20 * log10(rms)
        } else {
            avgPower = -100.0  // Silence
        }

        // Normalize to 0.0 - 1.0 range
        let normalizedLevel = max(0.0, min(1.0, (avgPower + 50.0) / 50.0))

        return normalizedLevel
    }

    // MARK: - Remote Audio Playback

    func playRemoteAudio(from participantId: UUID, audioData: Data) {
        guard let buffer = audioConverter.decode(data: audioData) else {
            print("Failed to decode audio data from \(participantId)")
            return
        }

        // Get or create audio player for this participant
        let player = getOrCreatePlayer(for: participantId)

        // Queue buffer for playback
        queueBuffer(buffer, for: participantId, player: player)
    }

    private func getOrCreatePlayer(for participantId: UUID) -> AVAudioPlayerNode {
        if let existingPlayer = audioPlayers[participantId] {
            return existingPlayer
        }

        // Create new player
        let player = AVAudioPlayerNode()

        guard let engine = audioEngine,
              let format = audioFormat else {
            return player
        }

        // Attach to engine
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Start player
        player.play()

        audioPlayers[participantId] = player
        playerBufferQueues[participantId] = []

        print("Created audio player for participant: \(participantId)")
        return player
    }

    private func queueBuffer(_ buffer: AVAudioPCMBuffer, for participantId: UUID, player: AVAudioPlayerNode) {
        // Schedule buffer for playback
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.onBufferComplete(for: participantId)
            }
        }

        // Mark as active speaker
        activeSpeakers.insert(participantId)

        // Remove from active speakers after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.activeSpeakers.remove(participantId)
        }
    }

    private func onBufferComplete(for participantId: UUID) {
        // Buffer finished playing
        // Could check queue and schedule next buffer
    }

    func removePlayer(for participantId: UUID) {
        guard let player = audioPlayers[participantId] else { return }

        player.stop()
        audioEngine?.detach(player)

        audioPlayers.removeValue(forKey: participantId)
        playerBufferQueues.removeValue(forKey: participantId)
        activeSpeakers.remove(participantId)

        print("Removed audio player for participant: \(participantId)")
    }

    // MARK: - Cleanup

    func cleanup() {
        stopRecording()

        // SAFETY: Copy keys before iteration to avoid mutating dictionary while iterating
        let playerIDs = Array(audioPlayers.keys)
        for id in playerIDs {
            removePlayer(for: id)
        }

        audioEngine = nil
        inputNode = nil

        print("Voice chat cleaned up")
    }

    deinit {
        cleanup()
    }
}

// MARK: - Audio Converter

class AudioConverter {
    /// Encode audio buffer to compressed data for network transmission
    func encode(buffer: AVAudioPCMBuffer, quality: Float) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        let channelDataValue = channelData.pointee

        // Simple 16-bit PCM encoding
        var encodedData = Data()
        encodedData.reserveCapacity(frameLength * 2) // 2 bytes per sample

        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            // Convert float (-1.0 to 1.0) to Int16
            let intSample = Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))

            withUnsafeBytes(of: intSample.littleEndian) { bytes in
                encodedData.append(contentsOf: bytes)
            }
        }

        // Add metadata header
        var header = AudioPacketHeader(
            sampleRate: UInt32(buffer.format.sampleRate),
            channels: UInt16(buffer.format.channelCount),
            frameLength: UInt32(frameLength)
        )

        var packetData = Data()
        withUnsafeBytes(of: &header) { bytes in
            packetData.append(contentsOf: bytes)
        }
        packetData.append(encodedData)

        return packetData
    }

    /// Decode compressed data back to audio buffer
    func decode(data: Data) -> AVAudioPCMBuffer? {
        // Extract header
        guard data.count >= MemoryLayout<AudioPacketHeader>.size else { return nil }

        let header = data.withUnsafeBytes { bytes -> AudioPacketHeader in
            bytes.load(as: AudioPacketHeader.self)
        }

        let audioData = data.dropFirst(MemoryLayout<AudioPacketHeader>.size)

        // Create buffer
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(header.sampleRate),
                                         channels: AVAudioChannelCount(header.channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                           frameCapacity: header.frameLength) else {
            return nil
        }

        buffer.frameLength = header.frameLength

        guard let channelData = buffer.floatChannelData else { return nil }

        // Decode Int16 samples back to Float
        let channelDataPointer = channelData.pointee
        var offset = 0

        for i in 0..<Int(header.frameLength) {
            guard offset + 1 < audioData.count else { break }

            let byte1 = audioData[audioData.startIndex + offset]
            let byte2 = audioData[audioData.startIndex + offset + 1]

            let intSample = Int16(byte1) | (Int16(byte2) << 8)
            channelDataPointer[i] = Float(intSample) / Float(Int16.max)

            offset += 2
        }

        return buffer
    }
}

// MARK: - Supporting Types

struct AudioPacketHeader {
    let sampleRate: UInt32
    let channels: UInt16
    let frameLength: UInt32
}

enum VoiceChatError: Error {
    case permissionDenied
    case audioEngineNotInitialized
    case encodingFailed
    case decodingFailed
}

// MARK: - Audio Level Monitor

extension VoiceChatManager {
    /// Get formatted audio level string for UI
    var audioLevelString: String {
        let bars = Int(audioLevel * 10)
        return String(repeating: "▂", count: max(0, 10 - bars)) +
               String(repeating: "▆", count: bars)
    }

    /// Check if currently speaking (audio level above threshold)
    var isSpeaking: Bool {
        return audioLevel > 0.1
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let voiceChatStarted = Notification.Name("voiceChatStarted")
    static let voiceChatStopped = Notification.Name("voiceChatStopped")
    static let voiceChatMuteChanged = Notification.Name("voiceChatMuteChanged")
}
