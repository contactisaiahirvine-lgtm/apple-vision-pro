import Foundation
import RealityKit
import AVFoundation
import Combine

/// Manages 3D positional audio for game objects
@MainActor
class SpatialAudioManager: ObservableObject {

    // MARK: - Published Properties

    @Published var activeSounds: [UUID: AudioPlayback] = [:]
    @Published var masterVolume: Float = 1.0

    // MARK: - Private Properties

    private weak var arView: ARView?
    private var audioResources: [String: AudioFileResource] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Listener (camera) position
    private var listenerPosition: SIMD3<Float> = .zero
    private var listenerForward: SIMD3<Float> = SIMD3(0, 0, -1)

    // Audio configuration
    private let maxDistance: Float = 50.0  // Max audible distance
    private let referenceDistance: Float = 1.0  // Distance at which volume is 100%

    // MARK: - Initialization

    init() {
        print("SpatialAudioManager initialized")
    }

    func setup(arView: ARView) {
        self.arView = arView
        configureAudioSession()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure for spatial audio
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .allowAirPlay]
            )
            try audioSession.setActive(true)

            print("Audio session configured for spatial audio")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Audio Loading

    /// Preload audio file
    func preloadAudio(named filename: String) async throws {
        guard audioResources[filename] == nil else {
            print("Audio '\(filename)' already loaded")
            return
        }

        // Load from bundle
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            throw SpatialAudioError.fileNotFound(filename)
        }

        do {
            let resource = try await AudioFileResource(contentsOf: url)
            audioResources[filename] = resource
            print("Loaded audio: \(filename)")
        } catch {
            throw SpatialAudioError.loadFailed(filename, error)
        }
    }

    /// Preload multiple audio files
    func preloadAudioFiles(_ filenames: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for filename in filenames {
                group.addTask { [weak self] in
                    do {
                        try await self?.preloadAudio(named: filename)
                    } catch {
                        print("Failed to preload '\(filename)': \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Sound Playback

    /// Play sound at world position
    func playSound(named filename: String,
                   at position: SIMD3<Float>,
                   volume: Float = 1.0,
                   loop: Bool = false,
                   entity: Entity? = nil) -> UUID? {

        guard let resource = audioResources[filename] else {
            print("Audio '\(filename)' not loaded. Call preloadAudio first.")
            return nil
        }

        guard let arView = arView else { return nil }

        // Create audio playback controller
        let audioController = entity?.prepareAudio(resource)

        // If no entity provided, create temporary anchor
        let playbackEntity: Entity
        if let entity = entity {
            playbackEntity = entity
        } else {
            let anchor = AnchorEntity(world: position)
            arView.scene.addAnchor(anchor)
            playbackEntity = anchor
        }

        // Configure spatial audio
        playbackEntity.position = position

        // Play audio
        let playback = playbackEntity.playAudio(resource)

        // Configure looping
        if loop {
            // RealityKit doesn't have direct loop control
            // Would need to monitor completion and replay
        }

        // Store playback info
        let id = UUID()
        activeSounds[id] = AudioPlayback(
            id: id,
            filename: filename,
            position: position,
            volume: volume,
            isLooping: loop,
            entity: playbackEntity
        )

        print("Playing '\(filename)' at \(position)")

        return id
    }

    /// Play sound attached to entity
    func playSoundOn(entity: Entity,
                     named filename: String,
                     volume: Float = 1.0,
                     loop: Bool = false) -> UUID? {

        return playSound(
            named: filename,
            at: entity.position(relativeTo: nil),
            volume: volume,
            loop: loop,
            entity: entity
        )
    }

    /// Play 2D sound (non-spatial)
    func play2DSound(named filename: String,
                     volume: Float = 1.0,
                     loop: Bool = false) -> UUID? {

        // Play at listener position (will sound non-spatial)
        return playSound(
            named: filename,
            at: listenerPosition,
            volume: volume,
            loop: loop
        )
    }

    // MARK: - Sound Control

    /// Stop specific sound
    func stopSound(_ id: UUID) {
        if let playback = activeSounds[id] {
            // RealityKit doesn't provide stop - remove entity
            if !(playback.entity is AnchorEntity) {
                // Don't remove if it's a game entity, just stop audio component
            }

            activeSounds.removeValue(forKey: id)
            print("Stopped sound: \(id)")
        }
    }

    /// Stop all sounds
    func stopAllSounds() {
        for (id, _) in activeSounds {
            stopSound(id)
        }
    }

    /// Pause sound
    func pauseSound(_ id: UUID) {
        // RealityKit doesn't provide pause control directly
        // Would need custom implementation
    }

    /// Update sound position (for moving sources)
    func updateSoundPosition(_ id: UUID, position: SIMD3<Float>) {
        if var playback = activeSounds[id] {
            playback.position = position
            playback.entity.position = position
            activeSounds[id] = playback
        }
    }

    // MARK: - Listener Update

    /// Update listener (camera) position and orientation
    func updateListener(position: SIMD3<Float>, forward: SIMD3<Float>) {
        listenerPosition = position
        listenerForward = forward
    }

    /// Update listener from AR camera
    func updateListenerFromCamera() {
        guard let arView = arView else { return }

        let cameraTransform = arView.cameraTransform

        listenerPosition = SIMD3<Float>(
            cameraTransform.translation.x,
            cameraTransform.translation.y,
            cameraTransform.translation.z
        )

        listenerForward = SIMD3<Float>(
            -cameraTransform.matrix.columns.2.x,
            -cameraTransform.matrix.columns.2.y,
            -cameraTransform.matrix.columns.2.z
        )
    }

    // MARK: - Spatial Audio Calculations

    /// Calculate volume based on distance
    func calculateSpatialVolume(sourcePosition: SIMD3<Float>) -> Float {
        let distance = simd_distance(listenerPosition, sourcePosition)

        if distance <= referenceDistance {
            return 1.0
        }

        if distance >= maxDistance {
            return 0.0
        }

        // Inverse distance attenuation
        let attenuation = referenceDistance / distance

        return attenuation * masterVolume
    }

    /// Calculate stereo pan (-1.0 left, 1.0 right)
    func calculateStereoPan(sourcePosition: SIMD3<Float>) -> Float {
        // Get vector from listener to source
        let toSource = sourcePosition - listenerPosition

        // Get listener's right vector (perpendicular to forward)
        let listenerUp = SIMD3<Float>(0, 1, 0)
        let listenerRight = simd_normalize(simd_cross(listenerForward, listenerUp))

        // Project onto right vector
        let pan = simd_dot(simd_normalize(toSource), listenerRight)

        return pan
    }

    // MARK: - Audio Effects

    /// Play one-shot sound effect
    func playSFX(_ filename: String, at position: SIMD3<Float>, volume: Float = 1.0) {
        _ = playSound(named: filename, at: position, volume: volume, loop: false)
    }

    /// Play ambient loop
    func playAmbientLoop(_ filename: String, volume: Float = 0.5) -> UUID? {
        return play2DSound(named: filename, volume: volume, loop: true)
    }

    // MARK: - Cleanup

    func cleanup() {
        stopAllSounds()
        audioResources.removeAll()
        print("Spatial audio cleaned up")
    }
}

// MARK: - Audio Playback Info

struct AudioPlayback {
    let id: UUID
    let filename: String
    var position: SIMD3<Float>
    var volume: Float
    var isLooping: Bool
    let entity: Entity
}

// MARK: - Errors

enum SpatialAudioError: LocalizedError {
    case fileNotFound(String)
    case loadFailed(String, Error)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Audio file '\(filename)' not found in bundle"
        case .loadFailed(let filename, let error):
            return "Failed to load '\(filename)': \(error.localizedDescription)"
        case .playbackFailed(let filename):
            return "Failed to play '\(filename)'"
        }
    }
}

// MARK: - Audio Source Component (for ECS)

struct AudioSourceComponent: Component {
    var audioFileName: String
    var isPlaying: Bool = false
    var isLooping: Bool = false
    var volume: Float = 1.0
    var spatialBlend: Float = 1.0  // 0.0 = 2D, 1.0 = full 3D
    var playbackID: UUID?

    init(audioFileName: String, isLooping: Bool = false,
         volume: Float = 1.0, spatialBlend: Float = 1.0) {
        self.audioFileName = audioFileName
        self.isLooping = isLooping
        self.volume = volume
        self.spatialBlend = spatialBlend
    }
}

// MARK: - Spatial Audio System (for ECS)

@MainActor
class SpatialAudioSystem: System {
    let name = "SpatialAudioSystem"
    let priority = 5

    weak var audioManager: SpatialAudioManager?

    init(audioManager: SpatialAudioManager) {
        self.audioManager = audioManager
    }

    func onAdd(to ecsManager: ECSManager) {
        // Update listener position
        audioManager?.updateListenerFromCamera()
    }

    func update(deltaTime: TimeInterval, ecsManager: ECSManager) {
        guard let audioManager = audioManager else { return }

        // Update listener
        audioManager.updateListenerFromCamera()

        // Process audio source components
        let entities = ecsManager.entitiesWith([TransformComponent.self, AudioSourceComponent.self])

        for entity in entities {
            guard let transform: TransformComponent = ecsManager.getComponent(for: entity),
                  var audioSource: AudioSourceComponent = ecsManager.getComponent(for: entity) else {
                continue
            }

            // Update position if sound is playing
            if audioSource.isPlaying, let playbackID = audioSource.playbackID {
                audioManager.updateSoundPosition(playbackID, position: transform.position)
            }

            // Start sound if requested
            if audioSource.isPlaying && audioSource.playbackID == nil {
                let id = audioManager.playSound(
                    named: audioSource.audioFileName,
                    at: transform.position,
                    volume: audioSource.volume,
                    loop: audioSource.isLooping
                )

                audioSource.playbackID = id
                ecsManager.updateComponent(audioSource, for: entity)
            }

            // Stop sound if requested
            if !audioSource.isPlaying, let playbackID = audioSource.playbackID {
                audioManager.stopSound(playbackID)
                audioSource.playbackID = nil
                ecsManager.updateComponent(audioSource, for: entity)
            }
        }
    }
}
