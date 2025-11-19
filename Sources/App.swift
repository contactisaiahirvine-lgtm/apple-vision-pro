import SwiftUI
import RealityKit

@main
struct VisionProARGameApp: App {
    @StateObject private var gameManager = GameManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var spatialTrackingManager = SpatialTrackingManager()
    @StateObject private var physicsManager = PhysicsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
                .environmentObject(spatialTrackingManager)
                .environmentObject(physicsManager)
                .onAppear {
                    // Setup spatial tracking listeners in game manager
                    gameManager.setupSpatialTrackingListeners(manager: spatialTrackingManager)

                    // Setup physics system
                    if GameConfig.physicsEnabled {
                        gameManager.setupPhysics(manager: physicsManager)
                    }

                    // Setup voice chat system
                    gameManager.setupVoiceChat()
                    networkManager.setupVoiceChatForwarding()

                    // Setup 3D asset placement system
                    gameManager.setupAssetPlacement()
                }
        }

        ImmersiveSpace(id: "GameSpace") {
            ImmersiveGameView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
                .environmentObject(spatialTrackingManager)
                .environmentObject(physicsManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
