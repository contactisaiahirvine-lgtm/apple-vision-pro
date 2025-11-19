import SwiftUI
import RealityKit

struct ContentView: View {
    @EnvironmentObject var gameManager: GameManager
    @EnvironmentObject var networkManager: NetworkManager
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            Text("Vision Pro AR Game")
                .font(.extraLargeTitle)
                .padding()

            // Connection Status
            HStack {
                Circle()
                    .fill(networkManager.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(networkManager.isConnected ? "Connected" : "Disconnected")
            }

            // Player Info
            if let player = gameManager.localPlayer {
                Text("Player: \(player.name)")
                    .font(.title)
            }

            // Game Controls
            VStack(spacing: 15) {
                Button("Start AR Game") {
                    Task {
                        await openImmersiveSpace(id: "GameSpace")
                        gameManager.startGame()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(gameManager.isGameActive)

                Button("Host Multiplayer Session") {
                    networkManager.startHosting()
                }
                .buttonStyle(.bordered)
                .disabled(networkManager.isConnected)

                Button("Join Multiplayer Session") {
                    networkManager.startBrowsing()
                }
                .buttonStyle(.bordered)
                .disabled(networkManager.isConnected)

                if gameManager.isGameActive {
                    Button("Stop Game") {
                        Task {
                            await dismissImmersiveSpace()
                            gameManager.stopGame()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

            // Connected Players
            if !networkManager.connectedPeers.isEmpty {
                VStack(alignment: .leading) {
                    Text("Connected Players:")
                        .font(.headline)
                    ForEach(networkManager.connectedPeers, id: \.self) { peer in
                        Text("• \(peer.displayName)")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(10)
            }
        }
        .padding()
    }
}
