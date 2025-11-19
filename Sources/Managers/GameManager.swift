import Foundation
import RealityKit
import SwiftUI
import Combine
import ObjectiveC

@MainActor
class GameManager: ObservableObject {
    @Published var isGameActive = false
    @Published var localPlayer: Player?
    @Published var remotePlayers: [UUID: Player] = [:]

    private var rootEntity: Entity?
    private var gameLoopTask: Task<Void, Never>?
    private var lastUpdateTime: Date?

    // Movement state
    private var currentDragTranslation: CGSize = .zero
    private var movementDirection: SIMD3<Float> = .zero

    init() {
        // Initialize local player
        let playerName = "Player_\(Int.random(in: 1000...9999))"
        self.localPlayer = Player(name: playerName, isLocal: true)

        // Setup network listeners
        setupNetworkListeners()
    }

    // MARK: - Scene Setup

    func setupScene(content: RealityViewContent) async {
        // Create root entity
        let root = Entity()
        content.add(root)
        self.rootEntity = root

        // Setup lighting
        await setupLighting(root: root)

        // Create local player entity
        await createPlayerEntity(for: localPlayer!)
        if let playerEntity = localPlayer?.entity {
            root.addChild(playerEntity)
        }

        // Setup ground plane
        await setupGroundPlane(root: root)
    }

    func updateScene(content: RealityViewContent) {
        // Update remote players
        for (_, player) in remotePlayers {
            if player.entity?.parent == nil, let entity = player.entity {
                rootEntity?.addChild(entity)
            }
        }
    }

    private func setupLighting(root: Entity) async {
        // Add ambient lighting
        var ambientLight = AmbientLightComponent()
        ambientLight.intensity = 1000
        let lightEntity = Entity()
        lightEntity.components.set(ambientLight)
        root.addChild(lightEntity)
    }

    private func setupGroundPlane(root: Entity) async {
        // Create a ground plane for reference
        let groundMesh = MeshResource.generatePlane(width: 10, depth: 10)
        var groundMaterial = SimpleMaterial()
        groundMaterial.color = .init(tint: .gray.withAlphaComponent(0.3))

        let groundEntity = ModelEntity(mesh: groundMesh, materials: [groundMaterial])
        groundEntity.position = SIMD3<Float>(0, -0.5, 0)
        root.addChild(groundEntity)
    }

    // MARK: - Player Management

    private func createPlayerEntity(for player: Player) async {
        // Create a simple cube to represent the player
        let mesh = MeshResource.generateBox(size: 0.2)
        var material = SimpleMaterial()
        material.color = .init(tint: player.isLocal ? .blue : .red)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = player.position

        // Add collision component
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.2))]))

        player.entity = entity
    }

    func addRemotePlayer(_ player: Player) async {
        remotePlayers[player.id] = player
        await createPlayerEntity(for: player)

        if let entity = player.entity {
            rootEntity?.addChild(entity)
        }
    }

    func removeRemotePlayer(id: UUID) {
        if let player = remotePlayers[id] {
            player.entity?.removeFromParent()
            remotePlayers.removeValue(forKey: id)
        }
    }

    func updateRemotePlayer(data: PlayerNetworkData) {
        if let player = remotePlayers[data.id] {
            player.update(from: data)
        } else {
            // Create new remote player
            let newPlayer = Player(id: data.id, name: data.name, isLocal: false)
            newPlayer.update(from: data)
            Task {
                await addRemotePlayer(newPlayer)
            }
        }
    }

    // MARK: - Game Loop

    func startGame() {
        isGameActive = true
        localPlayer?.position = SIMD3<Float>(0, 1, -2)
    }

    func stopGame() {
        isGameActive = false
        stopGameLoop()
    }

    func startGameLoop() {
        lastUpdateTime = Date()

        gameLoopTask = Task {
            while !Task.isCancelled && isGameActive {
                let currentTime = Date()
                let deltaTime = Float(currentTime.timeIntervalSince(lastUpdateTime ?? currentTime))
                lastUpdateTime = currentTime

                updateGame(deltaTime: deltaTime)

                // Run at ~60 FPS
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    func stopGameLoop() {
        gameLoopTask?.cancel()
        gameLoopTask = nil
    }

    private func updateGame(deltaTime: Float) {
        // Update local player
        if let localPlayer = localPlayer {
            // Apply movement based on drag input
            if length(movementDirection) > 0 {
                localPlayer.move(direction: movementDirection, speed: 2.0)
            }

            localPlayer.updatePosition(deltaTime: deltaTime)

            // Broadcast local player state
            NotificationCenter.default.post(
                name: .playerStateUpdated,
                object: nil,
                userInfo: ["player": localPlayer]
            )
        }

        // Update remote players
        for (_, player) in remotePlayers {
            player.updatePosition(deltaTime: deltaTime)
        }
    }

    // MARK: - Input Handling

    func handleDragGesture(_ value: DragGesture.Value) {
        currentDragTranslation = value.translation

        // Convert drag to movement direction
        let x = Float(value.translation.width) * 0.001
        let z = Float(value.translation.height) * 0.001

        movementDirection = SIMD3<Float>(x, 0, -z)
    }

    func handleDragGestureEnded(_ value: DragGesture.Value) {
        currentDragTranslation = .zero
        movementDirection = SIMD3<Float>(0, 0, 0)
    }

    func handleTap() {
        // Jump or perform action
        localPlayer?.velocity.y += 3.0
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let playerStateUpdated = Notification.Name("playerStateUpdated")
}
