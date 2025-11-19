import SwiftUI
import RealityKit

@main
struct VisionProARGameApp: App {
    @StateObject private var gameManager = GameManager()
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var spatialTrackingManager = SpatialTrackingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
                .environmentObject(spatialTrackingManager)
                .onAppear {
                    // Setup spatial tracking listeners in game manager
                    gameManager.setupSpatialTrackingListeners(manager: spatialTrackingManager)
                }
        }

        ImmersiveSpace(id: "GameSpace") {
            ImmersiveGameView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
                .environmentObject(spatialTrackingManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
