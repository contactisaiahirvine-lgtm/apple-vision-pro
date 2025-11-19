# Voice Chat System Documentation

## Overview

The Voice Chat system provides real-time voice communication for multiplayer AR gaming on Apple Vision Pro. It features low-latency audio capture, encoding, network transmission, and multi-participant playback with automatic voice activity detection.

### Key Features

- **Real-time Audio**: Low-latency audio capture and playback
- **Spatial Audio Ready**: Compatible with visionOS spatial audio capabilities
- **Voice Activity Detection**: Automatic detection of active speakers
- **Audio Level Monitoring**: Real-time audio level visualization
- **Mute Control**: Individual mute capability
- **Multi-participant**: Support for multiple simultaneous speakers
- **Network Optimized**: Efficient 16-bit PCM encoding for bandwidth optimization
- **Permission Handling**: Automatic microphone permission requests

---

## Architecture

### Components

```
┌─────────────────────┐
│  VoiceChatManager   │ ◄─── Audio Engine & Processing
└──────────┬──────────┘
           │
           ├─── Audio Capture (AVAudioEngine)
           ├─── Encoding (AudioConverter)
           ├─── Playback (AVAudioPlayerNode)
           └─── Level Monitoring

┌─────────────────────┐
│   NetworkManager    │ ◄─── Message Transport
└──────────┬──────────┘
           │
           └─── MultipeerConnectivity

┌─────────────────────┐
│   GameManager       │ ◄─── Integration Layer
└──────────┬──────────┘
           │
           └─── Voice Chat Extension
```

### Audio Pipeline

```
Microphone → AVAudioEngine → AudioConverter (Encode) → NetworkManager → Remote Devices
                                                                               │
                                                                               ▼
Local Speakers ◄─ AVAudioPlayerNode ◄─ AudioConverter (Decode) ◄─────────────┘
```

---

## How It Works

### 1. Audio Capture

When voice chat is started:

```swift
// VoiceChatManager.swift:72-99
func startRecording() async throws {
    // Request microphone permission
    let hasPermission = await requestMicrophonePermission()
    guard hasPermission else {
        throw VoiceChatError.permissionDenied
    }

    // Configure audio session for recording
    try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.defaultToSpeaker, .allowBluetooth])

    // Install tap on input node to capture audio
    input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, time in
        self.processAudioBuffer(buffer, time: time)
    }

    // Start the audio engine
    try engine.start()
}
```

**Audio Session Configuration:**
- Category: `.playAndRecord` - Enables simultaneous recording and playback
- Mode: `.voiceChat` - Optimized for voice communication
- Options:
  - `.defaultToSpeaker` - Output to speaker by default
  - `.allowBluetooth` - Support Bluetooth headsets

### 2. Audio Processing

Each audio buffer is processed in real-time:

```swift
// VoiceChatManager.swift:126-140
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    // Don't send if muted
    guard !isMuted else { return }

    // Calculate audio level for UI feedback
    updateAudioLevel(from: buffer)

    // Encode audio data for network transmission
    guard let audioData = audioConverter.encode(buffer: buffer, quality: audioQuality) else {
        return
    }

    // Send to network
    onAudioDataReady?(audioData)
}
```

**Audio Level Calculation:**
- Computes RMS (Root Mean Square) of audio samples
- Converts to decibel scale (dB)
- Normalizes to 0.0-1.0 range for UI display

### 3. Audio Encoding

Audio is encoded to 16-bit PCM format for efficient network transmission:

```swift
// VoiceChatManager.swift:261-295
func encode(buffer: AVAudioPCMBuffer, quality: Float) -> Data? {
    // Convert Float samples (-1.0 to 1.0) to Int16
    for i in 0..<frameLength {
        let sample = channelDataValue[i]
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

    // Prepend header to data
    packetData.append(header)
    packetData.append(encodedData)

    return packetData
}
```

**Encoding Specs:**
- Format: 16-bit PCM (2 bytes per sample)
- Sample Rate: 16,000 Hz (configurable)
- Channels: 1 (mono)
- Buffer Size: 1,024 frames
- Approximate Data Rate: 32 KB/s per speaker

### 4. Network Transmission

Encoded audio is sent via NetworkManager:

```swift
// GameManager+VoiceChat.swift:72-84
private func sendVoiceChat(audioData: Data) {
    guard let localPlayer = localPlayer else { return }

    // Create voice chat message with participant ID
    let message = NetworkMessage.voiceChat(
        participantID: localPlayer.id,
        audioData: audioData
    )

    // Broadcast to all connected peers
    NotificationCenter.default.post(
        name: .sendNetworkMessage,
        object: nil,
        userInfo: ["message": message]
    )
}
```

**Network Protocol:**
- Transport: MultipeerConnectivity
- Mode: `.reliable` (TCP-like, ensures delivery)
- Packet Structure:
  ```
  [NetworkMessage Header]
  [Participant UUID (16 bytes)]
  [Audio Header (10 bytes)]
  [PCM Audio Data (variable, ~2KB)]
  ```

### 5. Audio Decoding & Playback

Received audio is decoded and played back:

```swift
// VoiceChatManager.swift:161-172
func playRemoteAudio(from participantId: UUID, audioData: Data) {
    // Decode compressed data
    guard let buffer = audioConverter.decode(data: audioData) else {
        print("Failed to decode audio data from \(participantId)")
        return
    }

    // Get or create audio player for this participant
    let player = getOrCreatePlayer(for: participantId)

    // Queue buffer for playback
    queueBuffer(buffer, for: participantId, player: player)
}
```

**Player Management:**
- One `AVAudioPlayerNode` per remote participant
- Automatically created on first audio packet
- Attached to audio engine mixer
- Removed when participant disconnects

### 6. Voice Activity Detection

Active speakers are tracked automatically:

```swift
// VoiceChatManager.swift:201-216
private func queueBuffer(_ buffer: AVAudioPCMBuffer, for participantId: UUID,
                         player: AVAudioPlayerNode) {
    // Schedule buffer for playback
    player.scheduleBuffer(buffer) { [weak self] in
        DispatchQueue.main.async {
            self?.onBufferComplete(for: participantId)
        }
    }

    // Mark as active speaker
    activeSpeakers.insert(participantId)

    // Remove from active speakers after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.activeSpeakers.remove(participantId)
    }
}
```

---

## API Reference

### VoiceChatManager

Main class for voice chat management.

#### Properties

```swift
@Published var isRecording: Bool           // Recording state
@Published var isMuted: Bool               // Mute state
@Published var activeSpeakers: Set<UUID>   // Currently speaking participants
@Published var audioLevel: Float           // Local audio level (0.0-1.0)
```

#### Methods

```swift
// Start recording audio
func startRecording() async throws

// Stop recording audio
func stopRecording()

// Toggle mute (stops transmission but keeps recording)
func toggleMute()

// Play audio from remote participant
func playRemoteAudio(from participantId: UUID, audioData: Data)

// Remove player when participant leaves
func removePlayer(for participantId: UUID)

// Cleanup all resources
func cleanup()
```

#### Configuration

```swift
private let bufferSize: AVAudioFrameCount = 1024
private let audioQuality: Float = 0.5  // 0.0 to 1.0 (unused in current implementation)
private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
```

### GameManager Voice Chat Extension

Integration layer between VoiceChatManager and game systems.

#### Methods

```swift
// Setup voice chat system
func setupVoiceChat()

// Start voice chat recording
func startVoiceChat() async throws

// Stop voice chat recording
func stopVoiceChat()

// Toggle mute
func toggleVoiceMute()
```

#### Properties

```swift
var activeSpeakers: Set<UUID>    // Active speakers
var audioLevel: Float            // Local audio level
var isRecordingVoice: Bool       // Recording state
var isVoiceMuted: Bool           // Mute state
```

### NetworkManager

Voice chat message handling.

```swift
// Network message types
enum NetworkMessage: Codable {
    case voiceChat(participantID: UUID, audioData: Data)
    // ... other message types
}

// Setup voice chat forwarding
func setupVoiceChatForwarding()
```

### AudioConverter

Audio encoding and decoding utilities.

```swift
// Encode audio buffer to compressed data
func encode(buffer: AVAudioPCMBuffer, quality: Float) -> Data?

// Decode compressed data back to audio buffer
func decode(data: Data) -> AVAudioPCMBuffer?
```

---

## Usage Examples

### Basic Setup

```swift
// In App.swift
@main
struct VisionProARGameApp: App {
    @StateObject private var gameManager = GameManager()
    @StateObject private var networkManager = NetworkManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
                .onAppear {
                    // Initialize voice chat
                    gameManager.setupVoiceChat()
                    networkManager.setupVoiceChatForwarding()
                }
        }
    }
}
```

### Starting Voice Chat

```swift
// In your view or view model
Button("Start Voice Chat") {
    Task {
        do {
            try await gameManager.startVoiceChat()
        } catch VoiceChatError.permissionDenied {
            print("Microphone permission denied")
        } catch {
            print("Failed to start voice chat: \(error)")
        }
    }
}
```

### Mute Control

```swift
Button(gameManager.isVoiceMuted ? "Unmute" : "Mute") {
    gameManager.toggleVoiceMute()
}
.buttonStyle(.bordered)
.tint(gameManager.isVoiceMuted ? .red : .green)
```

### Audio Level Visualization

```swift
// Bar graph visualization
GeometryReader { geometry in
    ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.3))
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.green)
            .frame(width: geometry.size.width * CGFloat(gameManager.audioLevel))
    }
}
.frame(height: 8)
```

### Active Speaker Indicator

```swift
if !gameManager.activeSpeakers.isEmpty {
    HStack {
        Image(systemName: "waveform")
            .foregroundColor(.green)
        Text("\(gameManager.activeSpeakers.count) speaking")
            .font(.caption)
    }
}
```

### Custom Audio Processing

```swift
// Extend VoiceChatManager for custom processing
extension VoiceChatManager {
    func enableNoiseSuppression() {
        // Add noise gate
        let threshold: Float = -40.0 // dB

        // In processAudioBuffer, check level before sending
        let avgPower = calculatePower(from: buffer)
        guard avgPower > threshold else { return }

        // Continue with encoding...
    }
}
```

---

## Configuration

### Audio Quality

Adjust buffer size and sample rate for different quality/performance tradeoffs:

```swift
// In VoiceChatManager.swift
private let bufferSize: AVAudioFrameCount = 1024  // Lower = less latency, higher CPU
private let audioFormat = AVAudioFormat(
    standardFormatWithSampleRate: 16000,  // Higher = better quality, more bandwidth
    channels: 1
)
```

**Recommended Settings:**

| Use Case | Sample Rate | Buffer Size | Latency | Data Rate |
|----------|-------------|-------------|---------|-----------|
| High Quality | 48,000 Hz | 2048 | ~43ms | 96 KB/s |
| Balanced | 16,000 Hz | 1024 | ~64ms | 32 KB/s |
| Low Latency | 16,000 Hz | 512 | ~32ms | 32 KB/s |
| Minimal Bandwidth | 8,000 Hz | 512 | ~64ms | 16 KB/s |

### Audio Session Options

Customize audio routing:

```swift
// VoiceChatManager.swift:86
try audioSession.setCategory(
    .playAndRecord,
    mode: .voiceChat,
    options: [
        .defaultToSpeaker,     // Use speaker instead of earpiece
        .allowBluetooth,       // Support Bluetooth headsets
        .allowBluetoothA2DP,   // Support high-quality Bluetooth
        .allowAirPlay,         // Support AirPlay devices
        .mixWithOthers         // Mix with other audio
    ]
)
```

### Voice Activity Detection Threshold

Adjust sensitivity:

```swift
// In VoiceChatManager extension
var isSpeaking: Bool {
    return audioLevel > 0.1  // Adjust threshold (0.0-1.0)
}
```

---

## Permissions

### Info.plist Configuration

Microphone permission is required:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to enable voice chat with other players during multiplayer sessions.</string>
```

### Permission Flow

```swift
// Automatic permission request
func startRecording() async throws {
    let hasPermission = await requestMicrophonePermission()
    guard hasPermission else {
        throw VoiceChatError.permissionDenied
    }
    // Continue with setup...
}

// Check permission state
func requestMicrophonePermission() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
        return true
    case .denied:
        // User must enable in Settings
        return false
    case .undetermined:
        // Request permission
        return await AVAudioApplication.requestRecordPermission()
    }
}
```

---

## Troubleshooting

### Common Issues

#### 1. No Audio Capture

**Symptoms:** `audioLevel` always 0.0, no audio sent

**Causes:**
- Microphone permission denied
- Audio engine not started
- Input device not available

**Solutions:**
```swift
// Check permission
let permission = AVAudioApplication.shared.recordPermission
print("Microphone permission: \(permission)")

// Verify audio engine
guard audioEngine?.isRunning == true else {
    print("Audio engine not running")
    return
}

// Check input node
guard let input = audioEngine?.inputNode else {
    print("No input node available")
    return
}
```

#### 2. No Remote Audio Playback

**Symptoms:** Can't hear other players

**Causes:**
- Network messages not being received
- Audio decoder failing
- Player not attached to engine

**Solutions:**
```swift
// Verify network connectivity
NotificationCenter.default.addObserver(forName: .voiceChatReceived) { notification in
    print("Received voice chat from: \(notification.userInfo?["participantID"])")
}

// Check decoder
guard let buffer = audioConverter.decode(data: audioData) else {
    print("Decode failed - invalid audio data")
    return
}

// Verify player attachment
print("Active players: \(audioPlayers.count)")
```

#### 3. High Latency

**Symptoms:** Delayed audio, poor synchronization

**Causes:**
- Large buffer sizes
- Network congestion
- CPU overload

**Solutions:**
```swift
// Reduce buffer size
private let bufferSize: AVAudioFrameCount = 512  // Was 1024

// Monitor frame time
let start = Date()
updateGame(deltaTime: deltaTime)
let duration = Date().timeIntervalSince(start)
if duration > 0.016 {
    print("WARNING: Frame time \(duration * 1000)ms exceeds 16ms budget")
}

// Use unreliable mode for lower latency (at cost of quality)
try session.send(data, toPeers: connectedPeers, with: .unreliable)
```

#### 4. Echo/Feedback

**Symptoms:** Hearing your own voice from speakers

**Causes:**
- No echo cancellation
- Speaker volume too high
- Improper audio routing

**Solutions:**
```swift
// Enable echo cancellation (visionOS handles this automatically in .voiceChat mode)
try audioSession.setMode(.voiceChat)

// Use headphones
try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                             options: [.allowBluetooth])

// Lower speaker volume programmatically
audioEngine?.mainMixerNode.outputVolume = 0.5
```

#### 5. Crackling/Distortion

**Symptoms:** Poor audio quality, artifacts

**Causes:**
- Buffer underruns
- Sample rate mismatch
- Integer overflow in encoding

**Solutions:**
```swift
// Ensure sample rates match
let inputSampleRate = audioEngine?.inputNode.outputFormat(forBus: 0).sampleRate
let outputSampleRate = audioFormat?.sampleRate
guard inputSampleRate == outputSampleRate else {
    print("Sample rate mismatch!")
    return
}

// Clamp samples before encoding
let intSample = Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))

// Increase buffer size if needed
private let bufferSize: AVAudioFrameCount = 2048
```

---

## Performance Considerations

### CPU Usage

**Audio Processing:**
- Capture: ~2-5% CPU per recording session
- Encoding: ~1-2% CPU per buffer
- Playback: ~2-3% CPU per participant
- Total for 4-player session: ~15-25% CPU

**Optimization Tips:**
```swift
// 1. Reduce sample rate
private let audioFormat = AVAudioFormat(
    standardFormatWithSampleRate: 8000,  // Half the data
    channels: 1
)

// 2. Increase buffer size (reduces callback frequency)
private let bufferSize: AVAudioFrameCount = 2048

// 3. Disable audio level monitoring when not needed
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    guard !isMuted else { return }

    // Skip level calculation
    // updateAudioLevel(from: buffer)

    guard let audioData = audioConverter.encode(buffer: buffer) else { return }
    onAudioDataReady?(audioData)
}
```

### Memory Usage

**Per Participant:**
- Audio player: ~50 KB
- Buffer queue: ~10-20 KB
- Total: ~70 KB per participant

**Total for 8 participants:** ~560 KB

### Network Bandwidth

**Per Speaker:**
- Sample Rate: 16,000 Hz
- Bits per Sample: 16
- Channels: 1
- **Data Rate:** 32 KB/s (256 kbit/s)

**For 4 simultaneous speakers:** 128 KB/s (1 Mbit/s)

**Optimization:**
- Use voice activity detection to reduce bandwidth when silent
- Consider opus codec for better compression (future enhancement)

---

## Best Practices

### 1. Always Check Permissions

```swift
func startVoiceChat() async throws {
    let hasPermission = await requestMicrophonePermission()
    guard hasPermission else {
        // Show alert to user
        showPermissionDeniedAlert()
        throw VoiceChatError.permissionDenied
    }
    // Continue...
}
```

### 2. Cleanup on Disconnect

```swift
// In GameManager+VoiceChat.swift
NotificationCenter.default.publisher(for: .remotePlayerLeft)
    .sink { [weak self] notification in
        guard let playerID = notification.userInfo?["playerID"] as? UUID else { return }
        self?.voiceChatManager?.removePlayer(for: playerID)
    }
    .store(in: &cancellables)
```

### 3. Handle Audio Interruptions

```swift
// Listen for audio session interruptions
NotificationCenter.default.addObserver(
    forName: AVAudioSession.interruptionNotification,
    object: nil,
    queue: .main
) { notification in
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
        return
    }

    switch type {
    case .began:
        // Pause voice chat
        voiceChatManager?.stopRecording()
    case .ended:
        // Resume if appropriate
        guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
            Task {
                try? await voiceChatManager?.startRecording()
            }
        }
    }
}
```

### 4. Implement Push-to-Talk (Optional)

```swift
// In your view
Button("Hold to Talk") {
    // Start recording
    Task {
        try? await gameManager.startVoiceChat()
    }
}
.onLongPressGesture(minimumDuration: .infinity) {
    // Never completes - acts as hold button
} onPressingChanged: { isPressing in
    if !isPressing {
        // Released - stop recording
        gameManager.stopVoiceChat()
    }
}
```

### 5. Monitor Audio Quality

```swift
// Add quality metrics
extension VoiceChatManager {
    private func logAudioQuality() {
        guard let engine = audioEngine,
              let inputFormat = inputNode?.outputFormat(forBus: 0) else { return }

        print("""
        Audio Quality Metrics:
        - Sample Rate: \(inputFormat.sampleRate) Hz
        - Channels: \(inputFormat.channelCount)
        - Engine Running: \(engine.isRunning)
        - Active Speakers: \(activeSpeakers.count)
        - Audio Level: \(audioLevel)
        """)
    }
}
```

---

## Future Enhancements

### Planned Features

1. **Spatial Audio Integration**
   - Position audio sources at player locations in 3D space
   - Use RealityKit AudioPlaybackComponent

2. **Codec Improvements**
   - Implement Opus codec for better compression
   - Adaptive bitrate based on network conditions

3. **Noise Suppression**
   - Apple's built-in voice processing
   - Custom noise gate implementation

4. **Network Optimization**
   - Use unreliable mode for lower latency
   - Implement jitter buffer
   - Forward error correction

5. **UI Enhancements**
   - Per-participant volume controls
   - Speaker labels with names
   - Connection quality indicators

### Example: Spatial Audio

```swift
// Future implementation
extension VoiceChatManager {
    func enableSpatialAudio(for participantId: UUID, at position: SIMD3<Float>) {
        guard let player = audioPlayers[participantId],
              let entity = remotePlayers[participantId]?.entity else { return }

        // Create audio playback component
        var audioPlayback = AudioPlaybackComponent()
        audioPlayback.gain = 1.0

        // Position in 3D space
        entity.position = position
        entity.components.set(audioPlayback)

        print("Spatial audio enabled for \(participantId) at \(position)")
    }
}
```

---

## Conclusion

The Voice Chat system provides a robust foundation for real-time voice communication in multiplayer AR experiences. It balances audio quality, latency, and bandwidth efficiency while maintaining ease of use and integration with the existing game architecture.

For additional support, refer to:
- [README.md](README.md) - Project overview
- [QUICKSTART.md](QUICKSTART.md) - Setup guide
- [PHYSICS.md](PHYSICS.md) - Physics system documentation
- [SPATIAL_TRACKING.md](SPATIAL_TRACKING.md) - Spatial tracking documentation

---

**Last Updated:** 2025-11-19
**Version:** 1.0.0
**Compatibility:** visionOS 1.0+
