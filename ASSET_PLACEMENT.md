# 3D Asset Placement & Registration Documentation
## Apple Vision Pro AR Game Boilerplate

**Last Updated**: 2025-11-19
**Version**: 1.0.0
**Compatibility**: visionOS 1.0+

---

## Overview

The 3D Asset Placement system provides comprehensive functionality for inserting, positioning, and managing virtual 3D objects in the physical world using Apple Vision Pro. The system features proper world anchoring, network synchronization for multiplayer, and an intuitive user interface for asset management.

### Key Features

- **World-Anchored Placement**: Objects stay fixed in real-world positions using ARKit anchors
- **Multi-Format Support**: USDZ, Reality Composer files, and procedurally generated primitives
- **Raycast Placement**: Tap-to-place on detected surfaces
- **Object Manipulation**: Move, rotate, and scale placed objects
- **Network Sync**: Automatic synchronization of placed objects across multiplayer sessions
- **Asset Library**: Built-in catalog of primitive shapes and game objects
- **Persistence**: Save and load placement scenes
- **Collision & Physics**: Optional collision detection and physics simulation
- **Touch Gestures**: Tap to place, long-press to select
- **Visual Feedback**: Semi-transparent previews and selection highlighting

---

## Architecture

### Component Overview

```
┌─────────────────────┐
│   AssetManager      │ ◄─── Load & Cache 3D Models
└──────────┬──────────┘
           │
           ├─── USDZ Files
           ├─── Reality Files
           ├─── Generated Primitives
           └─── Remote URLs

┌─────────────────────┐
│  PlacementManager   │ ◄─── Place & Manipulate Objects
└──────────┬──────────┘
           │
           ├─── Raycast Placement
           ├─── Object Selection
           ├─── Transform Operations
           └─── Scene Persistence

┌─────────────────────┐
│   AnchorManager     │ ◄─── World Anchoring
└──────────┬──────────┘
           │
           ├─── World Anchors
           ├─── Plane Anchors
           ├─── Camera Anchors
           └─── World Map Persistence

┌─────────────────────┐
│   GameManager       │ ◄─── Network Synchronization
└──────────┬──────────┘
           │
           └─── MultipeerConnectivity
```

### Data Flow

```
User Tap → Raycast → Surface Detection → Create Anchor → Load Asset → Attach to Anchor → Network Broadcast

Remote Event → Decode → Load Asset → Create Anchor → Place Object → Update UI
```

---

## Getting Started

### Basic Setup

The asset placement system is automatically initialized when the app launches:

```swift
// In App.swift onAppear
gameManager.setupAssetPlacement()
```

This creates three managers:
1. **AssetManager** - Handles 3D model loading
2. **AnchorManager** - Manages world anchors
3. **PlacementManager** - Coordinates placement logic

### Accessing from UI

```swift
// In your view
@EnvironmentObject var gameManager: GameManager

// Access managers
if let assetManager = gameManager.assetManager,
   let placementManager = gameManager.placementManager {
    // Use managers...
}
```

---

## Asset Library

### Built-In Assets

The system includes 8 pre-configured assets:

**Primitives:**
- `cube` - 10cm blue cube with physics
- `sphere` - 5cm radius red sphere with physics
- `cylinder` - 15cm tall green cylinder with physics

**Game Objects:**
- `platform` - 30x2x30cm gray platform (static)
- `target` - 20x20x5cm orange target
- `spawn_point` - 15cm radius purple spawn marker

**Markers:**
- `marker` - 2cm yellow sphere (no collision)
- `wall` - 50x100x5cm wall section

### Asset Definition Structure

```swift
AssetDefinition(
    id: "cube",                    // Unique identifier
    name: "Cube",                  // Display name
    category: .primitive,          // Category for filtering
    source: .generated(...),       // Where to load from
    previewColor: .systemBlue,     // UI preview color
    defaultScale: 1.0,             // Initial scale
    hasCollision: true,            // Enable collision
    hasPhysics: true,              // Enable physics
    tags: ["basic", "shape"]       // Search tags
)
```

### Asset Sources

```swift
// From app bundle (.usdz file)
source: .bundle(filename: "MyModel")

// From Reality Composer scene
source: .reality(sceneName: "MyScene")

// Procedurally generated
source: .generated(type: .box(size: SIMD3(0.1, 0.1, 0.1)))

// From remote URL
source: .remote(url: URL(string: "https://...")!)
```

---

## Placing Objects

### Method 1: User Interaction (Recommended)

```swift
// 1. Enter placement mode
await placementManager.startPlacement(assetName: "cube")

// 2. User taps screen (handled automatically by PlacementManager)
// Object is placed at raycast hit point

// 3. Cancel if needed
placementManager.cancelPlacement()
```

### Method 2: Programmatic Placement

```swift
// Place directly at specific position
let position = SIMD3<Float>(0, 0.5, -1.0)  // 1m in front, 50cm up

try await gameManager.placeAsset("sphere", at: position)
```

### Method 3: Placement on Detected Planes

```swift
// Use AnchorManager to snap to nearest plane
if let snapped = anchorManager.snapToPlane(position: roughPosition) {
    try await gameManager.placeAsset("platform", at: snapped)
}
```

---

## Object Manipulation

### Selection

```swift
// Select object by ID
placementManager.selectedObject = placedObject

// Selection via UI (long-press gesture handled automatically)
```

### Movement

```swift
let newPosition = SIMD3<Float>(1, 0, -2)
placementManager.moveObject(selectedObject, to: newPosition)

// Notification sent automatically:
// .objectMoved with userInfo: ["object": object, "position": position]
```

### Rotation

```swift
// Rotate 45 degrees around Y-axis
placementManager.rotateObject(selectedObject, by: .pi / 4)

// Rotate -45 degrees
placementManager.rotateObject(selectedObject, by: -.pi / 4)
```

### Scaling

```swift
// Scale up by 20%
placementManager.scaleObject(selectedObject, by: 1.2)

// Scale down by 20%
placementManager.scaleObject(selectedObject, by: 0.8)
```

### Deletion

```swift
placementManager.deleteObject(selectedObject)

// Clear all objects
placementManager.clearAll()
```

---

## World Anchoring

### Anchor Types

**1. World Anchors** (Most Common)
```swift
// Create anchor at specific 3D position
let anchor = try await anchorManager.createWorldAnchor(
    at: SIMD3<Float>(0, 1, -2)
)
```

**2. Plane Anchors**
```swift
// Attach to detected ARPlaneAnchor
let anchor = anchorManager.createPlaneAnchor(on: arPlaneAnchor)
```

**3. Camera Anchors**
```swift
// Create at current camera position
let anchor = try await anchorManager.createCameraAnchor()
```

**4. Raycast Anchors**
```swift
// Create where screen point hits surface
let screenPoint = CGPoint(x: 200, y: 300)
let anchor = try await anchorManager.createRaycastAnchor(from: screenPoint)
```

### Anchor Management

```swift
// Get anchor by ID
if let anchor = anchorManager.getAnchor(id: anchorID) {
    // Use anchor...
}

// Check if anchor is still tracked
let isValid = anchorManager.isAnchorValid(anchor)

// Get distance from camera
if let distance = anchorManager.distanceFromCamera(to: anchor) {
    print("Object is \(distance)m away")
}

// Remove anchor
anchorManager.removeAnchor(anchor)

// Remove all anchors
anchorManager.removeAllAnchors()
```

---

## Network Synchronization

### Automatic Synchronization

All placement, movement, rotation, and deletion events are automatically synchronized across connected players:

```swift
// Local placement automatically broadcasts to remote players
try await gameManager.placeAsset("cube", at: position)

// Remote players receive and create matching object automatically
```

### Manual Broadcasting

```swift
// Custom placement data
let data = PlacementNetworkData(
    type: .placed,
    objectID: 42,
    assetName: "cube",
    position: SIMD3(0, 1, -2),
    rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
    scale: SIMD3(repeating: 1.0)
)

// Encode and send
if let encoded = try? JSONEncoder().encode(data) {
    let message = NetworkMessage.gameEvent(encoded)
    NotificationCenter.default.post(
        name: .sendNetworkMessage,
        object: nil,
        userInfo: ["message": message]
    )
}
```

### Listening for Remote Events

```swift
NotificationCenter.default.publisher(for: .remotePlacementReceived)
    .sink { notification in
        guard let data = notification.userInfo?["data"] as? Data else { return }
        // Handle remote placement...
    }
    .store(in: &cancellables)
```

---

## Persistence

### Saving Scenes

```swift
// Save current placement
let scene = placementManager.saveScene()

// Encode to JSON
let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
let jsonData = try encoder.encode(scene)

// Write to file
let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("placement_scene.json")
try jsonData.write(to: url)
```

### Loading Scenes

```swift
// Read from file
let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("placement_scene.json")
let jsonData = try Data(contentsOf: url)

// Decode
let decoder = JSONDecoder()
let scene = try decoder.decode(PlacementScene.self, from: jsonData)

// Load into scene
await placementManager.loadScene(scene)
```

### World Map Persistence

```swift
// Save AR world map with anchors
let worldMap = try await anchorManager.saveWorldMap()

// Archive world map
let archivedData = try NSKeyedArchiver.archivedData(
    withRootObject: worldMap,
    requiringSecureCoding: false
)

// Restore world map
if let worldMap = try? NSKeyedUnarchiver.unarchivedObject(
    ofClass: ARWorldMap.self,
    from: archivedData
) {
    anchorManager.loadWorldMap(worldMap)
}
```

---

## Custom Assets

### Adding Custom USDZ Models

1. **Add file to Xcode project** - Drag `.usdz` file into project

2. **Create asset definition**:

```swift
let customAsset = AssetDefinition(
    id: "my_custom_model",
    name: "My Custom Model",
    category: .custom,
    source: .bundle(filename: "MyModel"),  // MyModel.usdz
    previewColor: .systemPurple,
    defaultScale: 1.0,
    hasCollision: true,
    hasPhysics: false,
    tags: ["custom", "special"]
)
```

3. **Add to asset library**:

```swift
// In AssetLibrary.swift
static let builtInAssets: [AssetDefinition] = [
    // ... existing assets ...
    customAsset
]
```

### Loading from Remote URL

```swift
let remoteAsset = AssetDefinition(
    id: "remote_model",
    name: "Downloaded Model",
    category: .custom,
    source: .remote(url: URL(string: "https://example.com/model.usdz")!),
    previewColor: .systemTeal,
    defaultScale: 1.0
)

// Load (downloads automatically)
let entity = try await assetManager.loadAsset(named: "remote_model")
```

### Creating Procedural Assets

```swift
// Custom generated geometry
let procedural = AssetDefinition(
    id: "custom_box",
    name: "Custom Box",
    category: .primitive,
    source: .generated(type: .box(size: SIMD3(0.2, 0.3, 0.1))),
    previewColor: .systemIndigo,
    defaultScale: 1.0
)
```

---

## UI Integration

### Asset Browser

The `AssetPlacementView` provides a complete UI for asset management:

```swift
.sheet(isPresented: $showAssetPlacement) {
    if let assetManager = gameManager.assetManager,
       let placementManager = gameManager.placementManager {
        AssetPlacementView(
            assetManager: assetManager,
            placementManager: placementManager
        )
    }
}
```

**Features:**
- Category-based filtering
- Grid layout with color-coded previews
- Placement mode indicator
- List of placed objects with positions
- Selected object manipulation controls
- Delete confirmation dialogs

### Custom UI

Build your own placement UI:

```swift
struct CustomPlacementUI: View {
    @ObservedObject var placementManager: PlacementManager
    @ObservedObject var assetManager: AssetManager

    var body: some View {
        VStack {
            // Asset picker
            Picker("Asset", selection: $selectedAsset) {
                ForEach(assetManager.availableAssets) { asset in
                    Text(asset.name).tag(asset.id)
                }
            }

            // Place button
            Button("Place") {
                Task {
                    await placementManager.startPlacement(assetName: selectedAsset)
                }
            }

            // Placed objects list
            List(placementManager.placedObjects) { object in
                HStack {
                    Text(object.assetName)
                    Spacer()
                    Button("Delete") {
                        placementManager.deleteObject(object)
                    }
                }
            }
        }
    }
}
```

---

## Advanced Features

### Preloading Assets

```swift
// Preload commonly used assets for faster placement
await assetManager.preloadAssets(["cube", "sphere", "cylinder"])
```

### Cache Management

```swift
// Clear cache to free memory
assetManager.clearCache()

// Remove specific asset
assetManager.removeFromCache(assetName: "large_model")

// Check cache size
print("Cache size: \(assetManager.cacheSize) bytes")
```

### Anchor Visualization

```swift
// Show anchor debug info
anchorManager.visualizeAnchors(enabled: true)

// Adds visual indicators for all anchors
```

### Tracking Quality

```swift
// Check if AR tracking is stable
anchorManager.updateTrackingState()

if anchorManager.isTrackingStable {
    // Safe to place objects
} else {
    // Show warning to user
}
```

### Collision Detection

```swift
// Assets with hasCollision: true automatically get collision components

// Custom collision shape
let entity = try await assetManager.createInstance(of: "custom")
let shape = ShapeResource.generateBox(size: SIMD3(0.2, 0.2, 0.2))
entity.components.set(CollisionComponent(shapes: [shape]))
```

### Physics Simulation

```swift
// Assets with hasPhysics: true get physics bodies

// Custom physics properties
if let modelEntity = entity as? ModelEntity {
    let material = PhysicsMaterialResource.generate(
        friction: 0.8,
        restitution: 0.9  // Bouncy!
    )

    modelEntity.components.set(PhysicsBodyComponent(
        massProperties: .default,
        material: material,
        mode: .dynamic
    ))
}
```

---

## API Reference

### AssetManager

```swift
class AssetManager {
    // Load asset by name
    func loadAsset(named: String) async throws -> Entity

    // Create independent instance
    func createInstance(of assetName: String) async throws -> Entity

    // Preload for performance
    func preloadAssets(_ assetNames: [String]) async

    // Cache management
    func clearCache()
    func removeFromCache(assetName: String)

    // Properties
    @Published var availableAssets: [AssetDefinition]
    @Published var loadingAssets: Set<String>
    @Published var loadedAssets: [String: ModelEntity]
}
```

### PlacementManager

```swift
class PlacementManager {
    // Placement mode
    func startPlacement(assetName: String) async
    func cancelPlacement()

    // Object manipulation
    func moveObject(_ object: PlacedObject, to position: SIMD3<Float>)
    func rotateObject(_ object: PlacedObject, by angle: Float)
    func scaleObject(_ object: PlacedObject, by factor: Float)
    func deleteObject(_ object: PlacedObject)

    // Scene management
    func clearAll()
    func saveScene() -> PlacementScene
    func loadScene(_ scene: PlacementScene) async

    // Properties
    @Published var placedObjects: [PlacedObject]
    @Published var selectedObject: PlacedObject?
    @Published var placementMode: PlacementMode
}
```

### AnchorManager

```swift
class AnchorManager {
    // Anchor creation
    func createWorldAnchor(at position: SIMD3<Float>) async throws -> AnchorEntity
    func createPlaneAnchor(on planeAnchor: ARPlaneAnchor) -> AnchorEntity
    func createCameraAnchor() async throws -> AnchorEntity
    func createRaycastAnchor(from screenPoint: CGPoint) async throws -> AnchorEntity

    // Anchor management
    func removeAnchor(_ anchor: AnchorEntity)
    func removeAllAnchors()
    func getAnchor(id: UUID) -> AnchorEntity?

    // Utilities
    func snapToPlane(position: SIMD3<Float>) -> SIMD3<Float>?
    func isAnchorValid(_ anchor: AnchorEntity) -> Bool
    func distanceFromCamera(to anchor: AnchorEntity) -> Float?

    // Persistence
    func saveWorldMap() async throws -> ARWorldMap
    func loadWorldMap(_ worldMap: ARWorldMap)

    // Visualization
    func visualizeAnchors(enabled: Bool)

    // Properties
    @Published var worldAnchors: [UUID: AnchorEntity]
    @Published var isTrackingStable: Bool
    @Published var anchorCount: Int
}
```

---

## Notifications

### Local Notifications

```swift
// Object placed
NotificationCenter.default.post(name: .objectPlaced, object: nil,
    userInfo: ["object": placedObject])

// Object moved
NotificationCenter.default.post(name: .objectMoved, object: nil,
    userInfo: ["object": object, "position": newPosition])

// Object rotated
NotificationCenter.default.post(name: .objectRotated, object: nil,
    userInfo: ["object": object, "rotation": rotation])

// Object scaled
NotificationCenter.default.post(name: .objectScaled, object: nil,
    userInfo: ["object": object, "scale": newScale])

// Object deleted
NotificationCenter.default.post(name: .objectDeleted, object: nil,
    userInfo: ["objectID": objectID])
```

### Network Notifications

```swift
// Send network message
NotificationCenter.default.post(name: .sendNetworkMessage, object: nil,
    userInfo: ["message": networkMessage])

// Remote placement received
NotificationCenter.default.post(name: .remotePlacementReceived, object: nil,
    userInfo: ["data": placementData])
```

---

## Error Handling

### AssetError

```swift
do {
    let entity = try await assetManager.loadAsset(named: "missing")
} catch AssetError.assetNotFound(let name) {
    print("Asset '\(name)' not found")
} catch AssetError.fileNotFound(let filename) {
    print("File '\(filename)' not in bundle")
} catch AssetError.loadFailed(let name, let error) {
    print("Load failed: \(error)")
}
```

### AnchorError

```swift
do {
    let anchor = try await anchorManager.createWorldAnchor(at: position)
} catch AnchorError.arViewNotInitialized {
    print("ARView not set up")
} catch AnchorError.raycastFailed {
    print("No surface found")
} catch AnchorError.trackingLost {
    print("AR tracking lost")
}
```

### PlacementError

```swift
do {
    try await gameManager.placeAsset("cube", at: position)
} catch PlacementError.managersNotInitialized {
    print("Call setupAssetPlacement() first")
} catch PlacementError.assetNotFound {
    print("Asset doesn't exist")
}
```

---

## Performance Optimization

### Best Practices

1. **Preload Frequently Used Assets**
```swift
await assetManager.preloadAssets(["cube", "sphere", "cylinder"])
```

2. **Limit Active Objects**
```swift
// Monitor placed object count
if placementManager.placedObjects.count > 100 {
    // Warn user or auto-cleanup distant objects
}
```

3. **Use Appropriate Collision Shapes**
```swift
// Prefer simple shapes (sphere, box) over mesh collision
```

4. **Disable Physics When Not Needed**
```swift
AssetDefinition(..., hasPhysics: false)
```

5. **Clear Cache Periodically**
```swift
// When memory is low
assetManager.clearCache()
```

### Performance Metrics

- **Asset Loading**: ~50-200ms per USDZ file
- **Anchor Creation**: ~10-30ms
- **Raycast**: ~5-15ms
- **Network Sync**: ~20-50ms latency
- **Memory**: ~100KB per cached asset
- **Recommended Max Objects**: 50-100 simultaneous

---

## Troubleshooting

### Objects Not Appearing

**Check:**
1. ARView is properly initialized
2. Anchor manager setup called
3. Tracking quality is sufficient
4. Asset actually loaded (check assetManager.loadedAssets)

```swift
print("Placed objects: \(placementManager.placedObjects.count)")
print("Anchors: \(anchorManager.anchorCount)")
print("Tracking: \(anchorManager.isTrackingStable)")
```

### Objects Not Staying in Place

**Cause**: Poor tracking or anchor invalidation

**Fix:**
```swift
// Verify anchor is still valid
if !anchorManager.isAnchorValid(anchor) {
    // Recreate anchor
    let newAnchor = try await anchorManager.createWorldAnchor(at: position)
    // Reattach entity
}
```

### Network Sync Not Working

**Check:**
1. Players are connected
2. Asset placement system initialized on both devices
3. Asset exists in both asset libraries

```swift
print("Connected: \(networkManager.isConnected)")
print("Peers: \(networkManager.connectedPeers.count)")
```

### High Memory Usage

**Fix:**
```swift
// Clear unused assets
assetManager.clearCache()

// Limit placed objects
let maxObjects = 50
if placementManager.placedObjects.count > maxObjects {
    // Remove oldest
    placementManager.deleteObject(placementManager.placedObjects.first!)
}
```

---

## Examples

### Example 1: Simple Placement

```swift
// Initialize
gameManager.setupAssetPlacement()

// Place a cube
try await gameManager.placeAsset("cube", at: SIMD3(0, 1, -2))
```

### Example 2: Interactive Placement with UI

```swift
Button("Place Sphere") {
    Task {
        await placementManager.startPlacement(assetName: "sphere")
    }
}
// User taps screen → sphere placed automatically
```

### Example 3: Building a Structure

```swift
// Create a platform
let platformPos = SIMD3<Float>(0, 0, -2)
try await gameManager.placeAsset("platform", at: platformPos)

// Stack cubes on platform
for i in 0..<3 {
    let cubePos = platformPos + SIMD3(0, 0.1 * Float(i + 1), 0)
    try await gameManager.placeAsset("cube", at: cubePos)
}
```

### Example 4: Multiplayer Collaborative Building

```swift
// All players can place objects - automatically synchronized

// Player 1 places wall
try await gameManager.placeAsset("wall", at: SIMD3(-1, 0.5, -2))

// Player 2 sees wall appear automatically
// Player 2 places target on opposite side
try await gameManager.placeAsset("target", at: SIMD3(1, 0.5, -2))

// Both see both objects
```

### Example 5: Save and Load Level

```swift
// Save current level
let scene = placementManager.saveScene()
let data = try JSONEncoder().encode(scene)
UserDefaults.standard.set(data, forKey: "level_1")

// Load level later
if let data = UserDefaults.standard.data(forKey: "level_1"),
   let scene = try? JSONDecoder().decode(PlacementScene.self, from: data) {
    await placementManager.loadScene(scene)
}
```

---

## Future Enhancements

### Planned Features

1. **Snap-to-Grid** - Align objects to grid for precise placement
2. **Grouping** - Group objects and manipulate as one
3. **Templates** - Save object configurations as templates
4. **Undo/Redo** - Placement history management
5. **Asset Variants** - Color/texture variations of base assets
6. **Placement Constraints** - Rules for valid placement locations
7. **Import/Export** - Share scenes across devices
8. **Asset Marketplace** - Download community-created assets

---

## Conclusion

The 3D Asset Placement system provides a robust foundation for building AR experiences with persistent, multiplayer-synchronized objects. The modular architecture makes it easy to extend with custom assets, behaviors, and interactions.

For additional support, refer to:
- [README.md](README.md) - Project overview
- [QUICKSTART.md](QUICKSTART.md) - Setup guide
- [SPATIAL_TRACKING.md](SPATIAL_TRACKING.md) - Spatial tracking details
- [PHYSICS.md](PHYSICS.md) - Physics system documentation

---

**Last Updated**: 2025-11-19
**Version**: 1.0.0
