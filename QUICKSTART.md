# Quick Start Guide

Get your Apple Vision Pro AR game running in 5 minutes!

## Prerequisites

- Xcode 15.2 or later
- Apple Vision Pro device or simulator
- Basic knowledge of SwiftUI and Swift

## Step 1: Create New Xcode Project

1. Open Xcode
2. File → New → Project
3. Select **visionOS** tab → **App**
4. Fill in:
   - Product Name: `VisionProARGame`
   - Interface: `SwiftUI`
   - Language: `Swift`

## Step 2: Add Files to Project

Copy all files from this repository into your Xcode project:

```
Sources/
├── App.swift → Replace your existing App.swift
├── ContentView.swift → Replace your existing ContentView.swift
├── ImmersiveGameView.swift → Add to project
├── Models/
│   └── Player.swift → Add to project
├── Managers/
│   ├── GameManager.swift → Add to project
│   └── NetworkManager.swift → Add to project
├── Extensions/
│   └── GameManager+Networking.swift → Add to project
├── Utilities/
│   ├── InputController.swift → Add to project
│   └── EntityFactory.swift → Add to project
└── Config/
    └── GameConfig.swift → Add to project
```

## Step 3: Configure Info.plist

Add these keys to your `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access to enable multiplayer gaming.</string>

<key>NSBonjourServices</key>
<array>
    <string>_visionpro-game._tcp</string>
</array>
```

Or use the provided `Info.plist` file.

## Step 4: Build and Run

1. Select **Apple Vision Pro** as your target device (or simulator)
2. Press **⌘R** to build and run
3. Grant permissions when prompted

## Step 5: Test Multiplayer (Optional)

**On Device 1:**
1. Tap "Host Multiplayer Session"
2. Wait for connection

**On Device 2:**
1. Tap "Join Multiplayer Session"
2. Connection should happen automatically

**Both Devices:**
1. Tap "Start AR Game"
2. You should see each other's avatars!

## Common Issues

### Build Errors

**Error: "Cannot find type 'ModelEntity'"**
- Solution: Ensure `import RealityKit` is in the file

**Error: "Module not found"**
- Solution: Clean build folder (Shift+⌘+K) and rebuild

### Runtime Issues

**Players not connecting**
- Check: Both devices on same WiFi network
- Check: Local network permission granted
- Check: Bluetooth enabled

**App crashes on launch**
- Check: All files properly added to target
- Check: Info.plist configured correctly

## Next Steps

Now that you have the basic game running:

1. **Customize Player Appearance**: Modify `EntityFactory.createPlayer()`
2. **Add Game Objects**: Create new entities in `EntityFactory`
3. **Implement Game Logic**: Add rules in `GameManager`
4. **Enhance Movement**: Modify `InputController` for custom controls
5. **Add Sound**: Integrate spatial audio
6. **Create UI**: Build custom menus and HUD

## Example: Adding a Power-Up

### 1. Create Entity (EntityFactory.swift)

```swift
static func createPowerUp(at position: SIMD3<Float>) -> ModelEntity {
    let mesh = MeshResource.generateSphere(radius: 0.15)
    var material = SimpleMaterial()
    material.color = .init(tint: .yellow)

    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = position
    return entity
}
```

### 2. Add to Scene (GameManager.swift)

```swift
func setupScene(content: RealityViewContent) async {
    // ... existing code ...

    // Add power-up
    let powerUp = EntityFactory.createPowerUp(
        at: SIMD3<Float>(1, 1, -3)
    )
    root.addChild(powerUp)
}
```

### 3. Add Collision Detection (GameManager.swift)

```swift
private func updateGame(deltaTime: Float) {
    // ... existing code ...

    // Check collisions
    checkPowerUpCollisions()
}

private func checkPowerUpCollisions() {
    // Implement collision logic
}
```

## Resources

- Full documentation in [README.md](README.md)
- [RealityKit Tutorial](https://developer.apple.com/documentation/realitykit)
- [visionOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/visionos)

## Getting Help

- Check the main README.md for detailed documentation
- Review code comments for inline explanations
- Open an issue for bugs or questions

---

Happy Coding! 🚀
