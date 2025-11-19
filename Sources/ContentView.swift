import SwiftUI
import RealityKit

struct ContentView: View {
    @EnvironmentObject var gameManager: GameManager
    @EnvironmentObject var networkManager: NetworkManager
    @EnvironmentObject var spatialTrackingManager: SpatialTrackingManager
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var showSpatialDebug = false
    @State private var showAssetPlacement = false

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

            // Spatial Tracking Status
            HStack {
                Circle()
                    .fill(spatialTrackingManager.isTrackingActive ? Color.blue : Color.gray)
                    .frame(width: 12, height: 12)
                Text("Spatial: \(spatialTrackingManager.isTrackingActive ? "Active" : "Inactive")")
            }

            // Spatial Info
            if spatialTrackingManager.isTrackingActive {
                HStack(spacing: 20) {
                    VStack {
                        Text("\(spatialTrackingManager.detectedPlanes.count)")
                            .font(.title2)
                            .bold()
                        Text("Planes")
                            .font(.caption)
                    }
                    VStack {
                        Text("\(spatialTrackingManager.detectedCorners.count)")
                            .font(.title2)
                            .bold()
                        Text("Corners")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
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

                // Spatial Tracking Controls
                HStack(spacing: 10) {
                    Button(spatialTrackingManager.isTrackingActive ? "Stop Tracking" : "Start Tracking") {
                        Task {
                            if spatialTrackingManager.isTrackingActive {
                                spatialTrackingManager.stopTracking()
                            } else {
                                await spatialTrackingManager.startTracking()
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    if spatialTrackingManager.isTrackingActive {
                        Button(showSpatialDebug ? "Hide Debug" : "Show Debug") {
                            showSpatialDebug.toggle()
                            gameManager.toggleSpatialVisualization(
                                enabled: showSpatialDebug,
                                manager: spatialTrackingManager
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // 3D Asset Placement
                if gameManager.isGameActive {
                    Button("3D Asset Placement") {
                        showAssetPlacement = true
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // Voice Chat Controls
                if networkManager.isConnected && gameManager.isGameActive {
                    VStack(spacing: 10) {
                        Text("Voice Chat")
                            .font(.headline)

                        HStack(spacing: 10) {
                            Button(gameManager.isRecordingVoice ? "Stop Voice" : "Start Voice") {
                                Task {
                                    if gameManager.isRecordingVoice {
                                        gameManager.stopVoiceChat()
                                    } else {
                                        try? await gameManager.startVoiceChat()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(gameManager.isRecordingVoice ? .red : .blue)

                            if gameManager.isRecordingVoice {
                                Button(gameManager.isVoiceMuted ? "Unmute" : "Mute") {
                                    gameManager.toggleVoiceMute()
                                }
                                .buttonStyle(.bordered)
                                .tint(gameManager.isVoiceMuted ? .red : .green)
                            }
                        }

                        // Audio Level Indicator
                        if gameManager.isRecordingVoice && !gameManager.isVoiceMuted {
                            VStack(spacing: 5) {
                                Text("Audio Level")
                                    .font(.caption)
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
                            }
                            .padding(.horizontal)
                        }

                        // Active Speakers
                        if !gameManager.activeSpeakers.isEmpty {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.green)
                                Text("\(gameManager.activeSpeakers.count) speaking")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)

                    Divider()
                }

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
        .sheet(isPresented: $showAssetPlacement) {
            if let assetManager = gameManager.assetManager,
               let placementManager = gameManager.placementManager {
                AssetPlacementView(
                    assetManager: assetManager,
                    placementManager: placementManager
                )
                .environmentObject(gameManager)
            } else {
                Text("Asset placement system not initialized")
                    .padding()
            }
        }
    }
}
