import SwiftUI
import RealityKit
import ARKit

struct ImmersiveGameView: View {
    @EnvironmentObject var gameManager: GameManager
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var spatialTrackingManager: SpatialTrackingManager

    var body: some View {
        RealityView { content in
            // Setup the AR scene
            await gameManager.setupScene(content: content)
        } update: { content in
            // Update scene based on game state changes
            gameManager.updateScene(content: content)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    gameManager.handleDragGesture(value)
                }
                .onEnded { value in
                    gameManager.handleDragGestureEnded(value)
                }
        )
        .gesture(
            TapGesture()
                .onEnded { _ in
                    gameManager.handleTap()
                }
        )
        .onAppear {
            gameManager.startGameLoop()
        }
        .onDisappear {
            gameManager.stopGameLoop()
        }
    }
}
