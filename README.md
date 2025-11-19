# Apple Vision Pro AR Game Boilerplate

A comprehensive boilerplate for building multiplayer AR games on Apple Vision Pro using SwiftUI, RealityKit, and MultipeerConnectivity.

## Features

- **Immersive AR Experience**: Full mixed reality support using visionOS
- **Physics Simulation**: Complete rigid body dynamics with collisions, forces, and materials
- **Spatial Awareness**: Real-world plane and corner detection using ARKit
- **Player Movement**: Intuitive drag-based movement controls with physics
- **Multiplayer Support**: Peer-to-peer networking using MultipeerConnectivity
- **Real-time Synchronization**: Automatic player state synchronization across devices
- **Environment Understanding**: Automatic detection of floors, walls, and room geometry
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
│   │   ├── GameManager.swift            # Core game logic and state
│   │   ├── NetworkManager.swift         # Multiplayer networking
│   │   ├── SpatialTrackingManager.swift # Plane & corner detection
│   │   └── PhysicsManager.swift         # Physics simulation engine
│   ├── Models/
│   │   ├── Player.swift     # Player model and network data
│   │   └── PhysicsBody.swift # Physics body component
│   ├── Extensions/
│   │   ├── GameManager+Networking.swift       # Network event handlers
│   │   ├── GameManager+SpatialTracking.swift  # Spatial integration
│   │   ├── GameManager+Physics.swift          # Physics integration
│   │   └── Player+Physics.swift               # Player physics helpers
│   ├── Utilities/
│   │   ├── InputController.swift      # Input processing
│   │   ├── EntityFactory.swift        # RealityKit entity creation
│   │   ├── SpatialVisualizer.swift    # Spatial feature visualization
│   │   └── PhysicsDebugRenderer.swift # Physics debug visualization
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

### Starting Spatial Tracking

1. Launch the app
2. Tap "Start Tracking"
3. Move your device to scan the room
4. Watch as planes and corners are detected
5. Toggle "Show Debug" to visualize detected features

**What gets detected**:
- Floors and ceilings
- Walls and doors
- Tables and furniture
- Room corners and edges

### Starting a Single Player Game

1. Launch the app
2. (Optional) Enable spatial tracking first
3. Tap "Start AR Game"
4. The immersive AR view will open
5. Use drag gestures to move your player
6. Tap to jump

**With Spatial Tracking**:
- Player automatically snaps to detected floor
- Walls create invisible collision boundaries
- Items can spawn on detected surfaces

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
- Spatial tracking integration

### NetworkManager
Handles all multiplayer networking using MultipeerConnectivity:
- Automatic peer discovery
- Reliable data transmission
- Player state synchronization
- Connection management

### SpatialTrackingManager
Manages real-world spatial understanding using ARKit:
- **Plane Detection**: Automatic detection of floors, walls, tables, etc.
- **Corner Recognition**: Algorithmic detection of room corners and edges
- **Real-time Updates**: Continuous tracking of environment changes
- **Spatial Queries**: Find nearest planes, corners, and surfaces

**Corner Detection Methods**:
1. **Boundary Extraction**: Corners from plane edges
2. **Plane Intersection**: Corners where walls meet, or wall meets floor

See [SPATIAL_TRACKING.md](SPATIAL_TRACKING.md) for detailed documentation.

### PhysicsManager
Complete physics simulation system built from scratch:
- **Rigid Body Dynamics**: Mass, velocity, forces, and impulses
- **Collision Detection**: Sphere, box, and capsule colliders
- **Material Properties**: Friction, bounciness, and density
- **Collision Resolution**: Realistic physics response with restitution
- **Raycasting**: Query the physics world
- **Constraints**: Freeze position/rotation on specific axes

**Supported Features**:
- Fixed timestep simulation (60 Hz)
- Multiple motion types (dynamic, static, kinematic)
- Collision layers and masks
- Per-body and global collision callbacks
- Force, impulse, and torque application

See [PHYSICS.md](PHYSICS.md) for complete physics documentation.

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

## Spatial Tracking Features

### What You Get

**Automatic Detection**:
- ✅ Horizontal planes (floors, tables, desks)
- ✅ Vertical planes (walls, doors, windows)
- ✅ Plane classification (floor, wall, ceiling, table, etc.)
- ✅ Boundary corners from plane edges
- ✅ Intersection corners where planes meet
- ✅ Real-time updates as environment changes

**Visualization** (Debug Mode):
- Blue spheres: Boundary corners
- Green spheres: Intersection corners (room corners)
- Yellow lines: Plane boundaries
- Semi-transparent fills: Detected surfaces
- Normal indicators: Surface orientation

**Game Integration**:
- Dynamic spawn points based on room layout
- Wall collision detection
- Floor-level player snapping
- Surface-based item placement
- Spatial queries for gameplay

### Usage Example

```swift
// Get the spatial manager
@EnvironmentObject var spatialTrackingManager: SpatialTrackingManager

// Find nearest corner
let corner = spatialTrackingManager.getNearestCorner(to: playerPosition)

// Get all floors
let floors = spatialTrackingManager.getHorizontalPlanes()
    .filter { $0.classification == .floor }

// Find room corners for hiding spots
let corners = spatialTrackingManager.getCornersNear(
    position: playerPos,
    radius: 5.0
)
```

See **[SPATIAL_TRACKING.md](SPATIAL_TRACKING.md)** for complete documentation.

## Physics System

### Complete Rigid Body Simulation

**Features**:
- ✅ Mass, velocity, acceleration
- ✅ Forces and impulses
- ✅ Gravity simulation
- ✅ Collision detection (sphere, box, capsule)
- ✅ Material properties (friction, bounciness)
- ✅ Collision layers for filtering
- ✅ Constraints (freeze axes)
- ✅ Raycasting
- ✅ Collision callbacks

### Usage Example

```swift
// Create physics-enabled object
let body = PhysicsBody.builder()
    .at(position: SIMD3<Float>(0, 2, 0))
    .withMass(1.0)
    .withCollider(.sphere(radius: 0.5))
    .withMaterial(.rubber)  // Bouncy!
    .build()

physicsManager.addPhysicsBody(body)

// Apply force
body.addForce(SIMD3<Float>(10, 0, 0))

// Apply impulse (instant)
body.addImpulse(SIMD3<Float>(0, 5, 0))

// Raycast
if let hit = physicsManager.raycast(origin: pos, direction: dir) {
    print("Hit at: \(hit.point)")
}
```

### Physics Materials

Predefined materials:
- **Default**: Balanced properties
- **Ice**: Low friction (0.1)
- **Rubber**: High bounce (0.9)
- **Metal**: Smooth, medium bounce
- **Wood**: Natural feel
- **Bouncy**: Super bouncy (0.95)
- **Frictionless**: No friction

### Player Physics

Players automatically use physics when enabled:
```swift
player.setupPhysics(physicsManager: physicsManager)
player.moveWithPhysics(direction: dir, speed: 5.0)
player.jump(force: 300.0)
player.dash(direction: dir, force: 500.0)
```

See **[PHYSICS.md](PHYSICS.md)** for complete physics documentation.

## Future Enhancements

Potential additions to this boilerplate:

- [ ] Voice chat integration
- [ ] Game rooms/lobbies
- [ ] Persistent world state
- [ ] AI opponents using spatial awareness
- [ ] Power-ups and collectibles
- [ ] Score tracking and leaderboards
- [ ] Custom avatar support
- [ ] Gesture-based controls
- [ ] Spatial audio
- [ ] Hand tracking integration
- [ ] Occlusion using scene mesh
- [ ] Persistent spatial anchors

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
