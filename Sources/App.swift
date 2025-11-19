import SwiftUI
import RealityKit

@main
struct VisionProARGameApp: App {
    @StateObject private var gameManager = GameManager()
    @StateObject private var networkManager = NetworkManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
        }

        ImmersiveSpace(id: "GameSpace") {
            ImmersiveGameView()
                .environmentObject(gameManager)
                .environmentObject(networkManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
