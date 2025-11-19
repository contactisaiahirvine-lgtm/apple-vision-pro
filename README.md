# Apple Vision Pro AR Game Boilerplate

A comprehensive boilerplate for building multiplayer AR games on Apple Vision Pro using SwiftUI, RealityKit, and MultipeerConnectivity.

## Features

- **Immersive AR Experience**: Full mixed reality support using visionOS
- **Player Movement**: Intuitive drag-based movement controls with physics
- **Multiplayer Support**: Peer-to-peer networking using MultipeerConnectivity
- **Real-time Synchronization**: Automatic player state synchronization across devices
- **Extensible Architecture**: Clean, modular codebase ready for expansion

## Project Structure

```
VisionProARGame/
├── Package.swift                 # Swift Package Manager configuration
├── Sources/
│   ├── App.swift                # Main app entry point
│   ├── ContentView.swift        # Main menu UI
│   ├── ImmersiveGameView.swift  # AR game view
│   ├── Models/
│   │   └── Player.swift         # Player model and network data
│   ├── Managers/
│   │   ├── GameManager.swift    # Core game logic and state
│   │   └── NetworkManager.swift # Multiplayer networking
│   ├── Extensions/
│   │   └── GameManager+Networking.swift  # Network event handlers
│   ├── Utilities/
│   │   ├── InputController.swift        # Input processing
│   │   └── EntityFactory.swift          # RealityKit entity creation
│   └── Config/
│       └── GameConfig.swift     # Game configuration constants
```

## Requirements

- **Device**: Apple Vision Pro
- **OS**: visionOS 1.0 or later
- **Xcode**: 15.2 or later
- **Swift**: 5.9 or later

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd apple-vision-pro
```

### 2. Open in Xcode

Since this uses Swift Package Manager, you can:

**Option A: Create an Xcode Project**
1. Open Xcode
2. File → New → Project
3. Select "visionOS" → "App"
4. Copy all files from `Sources/` into your project
5. Copy `Package.swift` dependencies if needed

**Option B: Use Swift Package**
1. Add this as a dependency to your existing visionOS project
2. Import the module in your code

### 3. Build and Run

1. Select Apple Vision Pro Simulator or Device
2. Press Cmd+R to build and run
3. Grant necessary permissions when prompted

## How to Use

### Starting a Single Player Game

1. Launch the app
2. Tap "Start AR Game"
3. The immersive AR view will open
4. Use drag gestures to move your player
5. Tap to jump

### Starting a Multiplayer Session

**Host a Game:**
1. Tap "Host Multiplayer Session"
2. Wait for other players to join
3. Tap "Start AR Game" when ready

**Join a Game:**
1. Tap "Join Multiplayer Session"
2. The app will automatically discover and connect to hosts
3. Tap "Start AR Game" when connected

## Controls

| Input | Action |
|-------|--------|
| Drag | Move player horizontally |
| Tap | Jump |
| Two-finger pinch | (Reserved for future use) |

## Architecture Overview

### GameManager
Manages the core game state, player entities, and game loop. Runs at ~60 FPS and handles:
- Player movement and physics
- Scene setup and updates
- Entity management
- Game state broadcasting

### NetworkManager
Handles all multiplayer networking using MultipeerConnectivity:
- Automatic peer discovery
- Reliable data transmission
- Player state synchronization
- Connection management

### Player Model
Represents both local and remote players with:
- Position, rotation, and velocity
- Physics-based movement
- Network serialization/deserialization
- RealityKit entity binding

## Configuration

Edit `Sources/Config/GameConfig.swift` to customize:

```swift
// Player settings
static let defaultPlayerSpeed: Float = 2.0
static let jumpForce: Float = 3.0

// World settings
static let worldBoundsMin = SIMD3<Float>(-5, -1, -5)
static let worldBoundsMax = SIMD3<Float>(5, 5, 5)

// Network settings
static let maxPlayers = 8
static let networkUpdateRate: TimeInterval = 0.033
```

## Extending the Game

### Adding New Game Objects

Use `EntityFactory` to create custom entities:

```swift
// In EntityFactory.swift
static func createPowerUp(at position: SIMD3<Float>) -> ModelEntity {
    let mesh = MeshResource.generateSphere(radius: 0.1)
    var material = SimpleMaterial()
    material.color = .init(tint: .yellow)

    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = position
    return entity
}
```

### Adding Custom Network Messages

Extend `NetworkMessage` enum:

```swift
// In NetworkManager.swift
enum NetworkMessage: Codable {
    case playerUpdate(Data)
    case playerJoined(Data)
    case playerLeft(UUID)
    case gameEvent(Data)
    case customEvent(YourDataType)  // Add your custom message
}
```

### Adding Game Events

Create custom notifications:

```swift
extension Notification.Name {
    static let customGameEvent = Notification.Name("customGameEvent")
}

// Post event
NotificationCenter.default.post(name: .customGameEvent, object: nil)

// Listen for event in GameManager
NotificationCenter.default.publisher(for: .customGameEvent)
    .sink { notification in
        // Handle event
    }
    .store(in: &cancellables)
```

## Multiplayer Architecture

The multiplayer system uses a peer-to-peer architecture:

1. **Discovery**: Devices advertise and browse for peers on local network
2. **Connection**: Automatic invitation and acceptance
3. **Synchronization**: Each device broadcasts player state at ~30 Hz
4. **Authority**: Each client owns their player's state
5. **Reconciliation**: Remote players interpolate between updates

## Performance Considerations

- Game loop runs at 60 FPS
- Network updates sent at 30 Hz to reduce bandwidth
- Player entities use simple geometry for optimal performance
- Collision detection uses basic bounding boxes

## Troubleshooting

### Players Not Connecting

- Ensure both devices are on the same network
- Check that Bluetooth and WiFi are enabled
- Verify local network permissions are granted

### Poor Performance

- Reduce number of entities in scene
- Lower network update rate in GameConfig
- Simplify player entity geometry

### Player Movement Issues

- Check world bounds in GameConfig
- Verify friction and speed settings
- Ensure ground plane is at correct height

## Security Notes

This boilerplate uses MultipeerConnectivity with encryption enabled by default. For production use:

- Implement proper authentication
- Add user confirmation for connections
- Validate all network data
- Consider implementing server-authoritative logic for competitive games

## Future Enhancements

Potential additions to this boilerplate:

- [ ] Voice chat integration
- [ ] Game rooms/lobbies
- [ ] Persistent world state
- [ ] AI opponents
- [ ] Power-ups and collectibles
- [ ] Score tracking and leaderboards
- [ ] Custom avatar support
- [ ] Gesture-based controls
- [ ] Spatial audio
- [ ] Hand tracking integration

## License

This boilerplate is provided as-is for educational and development purposes.

## Contributing

Feel free to submit issues and enhancement requests!

## Resources

- [visionOS Documentation](https://developer.apple.com/visionos/)
- [RealityKit Documentation](https://developer.apple.com/documentation/realitykit)
- [MultipeerConnectivity Guide](https://developer.apple.com/documentation/multipeerconnectivity)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)

## Support

For questions and support, please open an issue in the repository.

---

Built with ❤️ for Apple Vision Pro
