# Lighting Compensation Documentation

## Overview

The Lighting Compensation system automatically analyzes environmental lighting conditions and applies them to inserted AR assets, ensuring virtual objects blend seamlessly with the real world. This creates realistic, properly lit AR experiences that adapt to changing lighting conditions in real-time.

**Key Benefit**: AR objects appear natural and integrated, matching the lighting, color temperature, and shadows of the real environment.

---

## What It Does

### Analyzes Environmental Lighting:
- **Ambient Intensity** - Overall brightness (in lumens)
- **Color Temperature** - Warm/cool tint (in Kelvin)
- **Directional Light** - Primary light source direction and intensity
- **HDR Environment** - High dynamic range environment textures

### Applies to AR Assets:
- Adjusts material colors based on ambient lighting
- Modifies brightness to match environment
- Applies warm/cool color tints
- Adds emissive glow in bright environments
- Creates matching directional shadows
- Uses image-based lighting (IBL) for reflections

### Updates in Real-Time:
- Continuously monitors lighting changes
- Automatically updates tracked assets
- Responds to moving from indoor to outdoor
- Adapts to time-of-day changes

---

## Setup

### Basic Setup

```swift
// In your initialization code (after ARView created)

// 1. Setup lighting estimation
gameManager.setupLighting(arView: arView, quality: .standard)

// 2. Start estimation
gameManager.startLightingEstimation()
```

### Setup with Custom Quality

```swift
// Quality levels: basic, standard, high, ultra
gameManager.setupLighting(arView: arView, quality: .high)

// Configure options
gameManager.setAutoLightingUpdates(true)
gameManager.setHDREnvironment(true)
gameManager.setShadowIntensity(0.8)

// Start
gameManager.startLightingEstimation()
```

---

## Quality Levels

| Level | Features | Performance | Use Case |
|-------|----------|-------------|----------|
| **Basic** | Ambient only | Very fast | Low-end devices, simple scenes |
| **Standard** | Ambient + color temp | Fast | Default, balanced quality |
| **High** | + Directional light | Medium | Better shadows and highlights |
| **Ultra** | + HDR environment | Slower | Maximum realism |

```swift
gameManager.setLightingQuality(.high)
```

---

## Usage

### Game Loop Integration

```swift
// In your game loop
func updateGame(deltaTime: Float) {
    // Update lighting estimation
    gameManager.updateLightingEstimation(deltaTime: TimeInterval(deltaTime))

    // Other updates...
}
```

### Apply Lighting to Assets

#### Automatic (Recommended)

```swift
// Place asset with automatic lighting
let entity = await gameManager.placeAssetWithLighting(
    named: "chair",
    at: SIMD3(0, 0, -2),
    track: true  // Auto-update as lighting changes
)
```

#### Manual

```swift
// Load asset
let entity = try await assetManager.loadAsset(named: "table")

// Apply current environmental lighting
gameManager.applyEnvironmentalLighting(to: entity, track: true)
```

#### Apply to Existing Entity

```swift
// Apply lighting to already-placed entity
gameManager.applyEnvironmentalLighting(to: myEntity, track: false)
```

### Add Directional Light

```swift
// Add environmental light source matching real world
if let light = gameManager.addEnvironmentalLight(to: arView.scene) {
    print("Directional light added")
}
```

---

## Presets

For testing or controlled environments, use lighting presets:

### Available Presets

```swift
// Indoor lighting (warm, lower intensity)
gameManager.useIndoorLighting()

// Outdoor lighting (cool, high intensity)
gameManager.useOutdoorLighting()

// Custom presets
gameManager.applyLightingPreset(.sunset)  // Warm, medium intensity
gameManager.applyLightingPreset(.night)   // Cool, low intensity
```

### Preset Details

| Preset | Intensity | Temperature | Use Case |
|--------|-----------|-------------|----------|
| **Indoor** | 500 lumens | 3500K (warm) | Office, home |
| **Outdoor** | 1800 lumens | 6500K (cool) | Daylight |
| **Sunset** | 800 lumens | 2500K (very warm) | Golden hour |
| **Night** | 100 lumens | 4000K | Low light |

---

## Query Lighting Conditions

### Get Current Conditions

```swift
// Get lighting conditions snapshot
if let conditions = gameManager.getCurrentLightingConditions() {
    print("Ambient: \(conditions.ambientIntensity) lumens")
    print("Temperature: \(conditions.ambientColorTemperature)K")
    print("Category: \(conditions.category.rawValue)")
}
```

### Quick Queries

```swift
// Get ambient light level (0.0 - 1.0)
let level = gameManager.getAmbientLightLevel()
if level < 0.2 {
    print("Too dark for optimal AR")
}

// Get color temperature
let temp = gameManager.getColorTemperature()
if temp < 3000 {
    print("Warm lighting (indoor/sunset)")
} else if temp > 5500 {
    print("Cool lighting (outdoor/overcast)")
}

// Get lighting category
let category = gameManager.getLightingCategory()
// Returns: .dark, .dim, .normal, .bright
```

### Check Suitability

```swift
// Is lighting good enough for AR?
if !gameManager.isLightingSuitable() {
    print("⚠️ Lighting too dark - recommend brighter environment")
}

// Show warnings
gameManager.checkLightingWarnings()
```

---

## Lighting Categories

The system classifies lighting into categories:

| Category | Light Level | Intensity Range | Environment Examples |
|----------|-------------|-----------------|---------------------|
| **Dark** | < 20% | < 400 lumens | Night, dark room |
| **Dim** | 20-40% | 400-800 lumens | Evening, low light |
| **Normal** | 40-70% | 800-1400 lumens | Indoor, overcast |
| **Bright** | > 70% | > 1400 lumens | Outdoor sun, bright indoor |

```swift
let category = gameManager.getLightingCategory()

switch category {
case .dark:
    showLowLightWarning()
case .dim:
    // OK but not ideal
case .normal:
    // Ideal for AR
case .bright:
    // Good, but may cause glare
}
```

---

## Configuration

### Auto-Update Settings

```swift
// Enable automatic updates to tracked entities
gameManager.setAutoLightingUpdates(true)

// Disable auto-updates (manual control)
gameManager.setAutoLightingUpdates(false)
```

### HDR Environment

```swift
// Enable HDR environment textures (better reflections)
gameManager.setHDREnvironment(true)

// Disable for better performance
gameManager.setHDREnvironment(false)
```

### Shadow Intensity

```swift
// Adjust shadow strength (0.0 - 1.0)
gameManager.setShadowIntensity(0.8)  // 80% shadow strength

// No shadows
gameManager.setShadowIntensity(0.0)

// Full shadows
gameManager.setShadowIntensity(1.0)
```

---

## Entity Tracking

### Track for Auto-Updates

```swift
// Apply lighting and track for updates
gameManager.applyEnvironmentalLighting(to: entity, track: true)

// Lighting will auto-update as environment changes
```

### Stop Tracking

```swift
// Stop tracking specific entity
gameManager.stopTrackingLighting(for: entity)

// Stop tracking all entities
gameManager.stopTrackingAllLighting()
```

### Why Track?

**Benefits:**
- Automatic updates as lighting changes
- Seamless indoor/outdoor transitions
- Adapts to time-of-day

**Trade-offs:**
- Small performance cost
- May change appearance unexpectedly

**Recommendation**: Track for realistic objects, don't track for stylized/game assets

---

## How It Works

### Lighting Estimation Pipeline

1. **ARKit Analysis**
   - ARKit provides light estimate from camera
   - Analyzes image brightness, color
   - Estimates directional light source

2. **Data Extraction**
   - Ambient intensity (lumens)
   - Color temperature (Kelvin)
   - Primary light direction vector
   - Spherical harmonics (advanced)

3. **Material Modification**
   - Adjusts base color tint
   - Scales intensity
   - Adds emissive component
   - Modifies material properties

4. **Real-Time Updates**
   - Updates every 0.1 seconds (10 Hz)
   - Applies to all tracked entities
   - Smooth transitions

### Color Temperature Conversion

The system converts color temperature (Kelvin) to RGB:

| Temperature | Color | Environment |
|-------------|-------|-------------|
| 2000K-3000K | Warm Orange | Candlelight, sunset |
| 3000K-4000K | Warm White | Incandescent bulbs |
| 4000K-5000K | Neutral White | Fluorescent, morning |
| 5000K-6500K | Cool White | Daylight |
| 6500K+ | Blue White | Overcast, shade |

### Material Adjustments

**PhysicallyBasedMaterial (PBR):**
- Base color tinted by ambient color
- Intensity scaled by ambient level
- Emissive added for bright environments
- Metallic/roughness preserved

**UnlitMaterial:**
- Color adjusted by ambient
- Simpler calculations
- No shadow/reflection changes

---

## Performance

### Update Cost

- **Estimation**: ~1-2ms per update
- **Material Updates**: ~0.5ms per entity
- **Update Frequency**: 10 Hz (every 0.1s)
- **Total**: ~2-5ms per frame (tracked entities)

### Optimization Tips

1. **Limit Tracked Entities**
   ```swift
   // Only track important objects
   gameManager.applyEnvironmentalLighting(to: hero, track: true)
   gameManager.applyEnvironmentalLighting(to: background, track: false)
   ```

2. **Reduce Quality**
   ```swift
   // Use lower quality for better performance
   gameManager.setLightingQuality(.basic)
   ```

3. **Disable HDR**
   ```swift
   // Disable expensive HDR environment
   gameManager.setHDREnvironment(false)
   ```

4. **Manual Updates**
   ```swift
   // Disable auto-updates, control manually
   gameManager.setAutoLightingUpdates(false)

   // Update only when needed
   if lightingChanged() {
       gameManager.applyLightingToAllAssets()
   }
   ```

---

## Examples

### Example 1: Simple Asset with Lighting

```swift
// Load and place asset with automatic lighting
let chair = await gameManager.placeAssetWithLighting(
    named: "modern_chair",
    at: SIMD3(1, 0, -2),
    track: true
)

// Chair now matches environmental lighting
// Will update automatically as light changes
```

### Example 2: Indoor/Outdoor Transition

```swift
// Detect environment change
func onEnvironmentChanged(isIndoor: Bool) {
    if isIndoor {
        gameManager.useIndoorLighting()
    } else {
        gameManager.useOutdoorLighting()
    }

    // All tracked entities updated automatically
}
```

### Example 3: Custom Lighting Response

```swift
// React to lighting changes
NotificationCenter.default.addObserver(forName: .lightingConditionsUpdated) { notification in
    guard let conditions = notification.userInfo?["conditions"] as? LightingConditions else { return }

    // Adjust gameplay based on lighting
    if conditions.category == .dark {
        enableNightVision()
    } else {
        disableNightVision()
    }

    // Change environment effects
    if conditions.ambientColorTemperature < 3000 {
        addWarmGlow()  // Sunset/indoor
    } else {
        removeWarmGlow()
    }
}
```

### Example 4: Multiple Objects

```swift
// Place multiple objects with lighting
let objects = ["table", "lamp", "plant", "rug"]

for objectName in objects {
    let entity = await gameManager.placeAssetWithLighting(
        named: objectName,
        at: randomPosition(),
        track: true
    )

    // All objects match environment lighting
}
```

### Example 5: Lighting-Aware Spawning

```swift
// Spawn objects based on lighting
func spawnEnemy() {
    let category = gameManager.getLightingCategory()

    let enemy: Entity
    if category == .dark || category == .dim {
        // Spawn stealth enemy in low light
        enemy = createStealthEnemy()
    } else {
        // Spawn normal enemy in good light
        enemy = createNormalEnemy()
    }

    gameManager.applyEnvironmentalLighting(to: enemy, track: true)
}
```

---

## Statistics & Debug

### Get Statistics

```swift
if let stats = gameManager.getLightingStats() {
    print("Status: \(stats.isActive ? "Active" : "Inactive")")
    print("Intensity: \(stats.ambientIntensity) lumens")
    print("Temperature: \(stats.colorTemperature)K")
    print("Category: \(stats.category.rawValue)")
    print("Tracked: \(stats.trackedEntityCount) entities")
}
```

### Get Summary

```swift
let summary = gameManager.getLightingSummary()
print(summary)

// Output:
// === Lighting Summary ===
// Status: Active
// Category: Normal
// Ambient: 1200 lumens
// Temperature: 5500K
// Primary Light: 800 lumens
// Tracked Entities: 5
// =======================
```

### Debug Output

```swift
gameManager.printLightingDebug()

// Output:
// === Lighting Estimation Debug ===
// Active: true
// Quality: Standard
// Ambient Intensity: 1200 lumens
// Color Temperature: 5500K
// Primary Light: 800 lumens
// Direction: (0.3, -1.0, 0.2)
// Category: Normal
// Tracked Entities: 5
// =================================
```

---

## Best Practices

### 1. Always Enable for Realistic Assets

```swift
// For realistic furniture, props, characters
gameManager.setupLighting(arView: arView, quality: .high)
```

### 2. Consider Stylized Assets

```swift
// For cartoon/stylized art, maybe skip lighting
// Or use lower quality
gameManager.setLightingQuality(.basic)
```

### 3. Track Important Objects Only

```swift
// Hero objects: track
gameManager.applyEnvironmentalLighting(to: mainCharacter, track: true)

// Background props: don't track
gameManager.applyEnvironmentalLighting(to: decoration, track: false)
```

### 4. Warn Users About Low Light

```swift
if !gameManager.isLightingSuitable() {
    showWarning("Please move to a brighter area for best AR experience")
}
```

### 5. Use Presets for Testing

```swift
// Test different lighting scenarios
#if DEBUG
    gameManager.applyLightingPreset(.indoor)  // Test indoor
    gameManager.applyLightingPreset(.sunset)  // Test sunset
#endif
```

### 6. Handle Extreme Conditions

```swift
let category = gameManager.getLightingCategory()

if category == .dark {
    // Too dark - show warning or switch to simplified mode
    useSimplifiedGraphics()
} else if category == .bright {
    // Very bright - reduce emissive/glow effects
    reduceBrightness()
}
```

---

## Integration with Existing Systems

### With Asset Placement

```swift
// Asset placement already tracks positions
// Add lighting automatically
placementManager.placeWithLighting(
    assetName: "vase",
    at: position,
    lightingManager: lightingManager!
)
```

### With ECS

```swift
// Create entity with lighting component
let entity = ecsManager.createEntity { builder in
    builder
        .with(TransformComponent(position: position))
        .with(RenderableComponent(assetName: "statue"))
        .with(LightingComponent(  // Custom component
            trackLighting: true,
            intensityMultiplier: 1.0
        ))
}

// Apply lighting
gameManager.applyEnvironmentalLighting(to: entity.renderEntity!)
```

### With Multiplayer

```swift
// All players see same lighting
// But applied locally based on their environment
// Sync asset placement, not lighting data
```

---

## Limitations

### Current Limitations

1. **ARKit Dependency**
   - Requires ARWorldTrackingConfiguration
   - Light estimate quality varies by device
   - Not available in all ARKit modes

2. **Material Support**
   - Works best with PBR materials
   - Limited support for custom shaders
   - Unlit materials get basic treatment

3. **Performance**
   - Updates all tracked entities every 0.1s
   - Can impact performance with many tracked objects
   - HDR environment is expensive

4. **Accuracy**
   - Estimates may not match perfectly
   - Depends on camera exposure
   - Affected by camera auto-adjust

### Workarounds

1. **Manual Control**
   ```swift
   // Disable auto-updates, apply manually
   gameManager.setAutoLightingUpdates(false)
   ```

2. **Selective Application**
   ```swift
   // Only apply to close/important objects
   if distance < 5.0 {
       applyLighting()
   }
   ```

3. **Fallback to Presets**
   ```swift
   // If ARKit estimate unavailable
   gameManager.useIndoorLighting()
   ```

---

## Troubleshooting

### Assets Too Dark/Bright

**Problem**: Objects don't match environment brightness
**Solution**:
```swift
// Check current conditions
gameManager.printLightingDebug()

// Adjust manually if needed
gameManager.applyLightingPreset(.outdoor)
```

### Colors Don't Match

**Problem**: Color temperature seems wrong
**Solution**:
```swift
let temp = gameManager.getColorTemperature()
print("Temperature: \(temp)K")

// If incorrect, use preset
if insideBuilding {
    gameManager.useIndoorLighting()
}
```

### Performance Issues

**Problem**: Frame rate drops with many tracked objects
**Solution**:
```swift
// Reduce quality
gameManager.setLightingQuality(.basic)

// Stop tracking some entities
gameManager.stopTrackingAllLighting()

// Apply manually
gameManager.applyLightingToAllAssets()
```

### Lighting Not Updating

**Problem**: Entities don't update as lighting changes
**Solution**:
```swift
// Ensure tracking enabled
gameManager.applyEnvironmentalLighting(to: entity, track: true)

// Check if updates enabled
gameManager.setAutoLightingUpdates(true)

// Verify estimation is running
if !lightingManager.isActive {
    gameManager.startLightingEstimation()
}
```

---

## API Reference

### Setup Methods

```swift
func setupLighting(arView: ARView, quality: LightingQuality = .standard)
func startLightingEstimation()
func stopLightingEstimation()
func toggleLightingEstimation()
```

### Update Methods

```swift
func updateLightingEstimation(deltaTime: TimeInterval)
```

### Apply Methods

```swift
func applyEnvironmentalLighting(to entity: Entity, track: Bool = true)
func applyLightingToAllAssets()
func placeAssetWithLighting(named: String, at: SIMD3<Float>, track: Bool = true) async -> Entity?
func addEnvironmentalLight(to scene: Scene) -> DirectionalLight?
```

### Preset Methods

```swift
func applyLightingPreset(_ preset: LightingPreset)
func useIndoorLighting()
func useOutdoorLighting()
```

### Query Methods

```swift
func getCurrentLightingConditions() -> LightingConditions?
func getAmbientLightLevel() -> Float
func getColorTemperature() -> Float
func getLightingCategory() -> LightingCategory
func isLightingSuitable() -> Bool
```

### Configuration Methods

```swift
func setLightingQuality(_ quality: LightingQuality)
func setAutoLightingUpdates(_ enabled: Bool)
func setHDREnvironment(_ enabled: Bool)
func setShadowIntensity(_ intensity: Float)
```

### Tracking Methods

```swift
func stopTrackingLighting(for entity: Entity)
func stopTrackingAllLighting()
```

### Statistics Methods

```swift
func getLightingStats() -> LightingStats?
func getLightingSummary() -> String
func printLightingDebug()
func checkLightingWarnings()
```

---

## Conclusion

The Lighting Compensation system ensures AR objects blend naturally with the real world by matching environmental lighting conditions. By automatically analyzing and applying ambient intensity, color temperature, and directional lighting, inserted assets appear realistic and properly integrated.

**Key Features:**
- Automatic environmental analysis
- Real-time lighting adaptation
- Material-aware compensation
- Configurable quality levels
- Preset lighting scenarios
- Performance-optimized updates

**Best For:**
- Realistic AR experiences
- Furniture/product visualization
- Architectural visualization
- Character/avatar integration
- Any AR content requiring realism

**Next Steps:**
1. Setup lighting estimation in your game
2. Apply to placed assets
3. Test in different environments
4. Adjust quality based on performance
5. Fine-tune for your specific use case

---

**Version**: 1.0.0
**Last Updated**: 2025-11-19
**Compatibility**: visionOS 1.0+
**Dependencies**: ARKit, RealityKit
