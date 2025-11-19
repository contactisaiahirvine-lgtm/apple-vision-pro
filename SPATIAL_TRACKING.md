# Spatial Tracking & Corner Recognition

This document explains how spatial tracking and corner recognition work in the Vision Pro AR Game boilerplate.

## Overview

Apple Vision Pro has **built-in spatial understanding** through ARKit's visionOS APIs. This boilerplate provides a complete implementation that accesses and utilizes these capabilities for game development.

## What's Built-In vs. What We Added

### Built-In (Apple Vision Pro Hardware/OS)

Apple Vision Pro provides through ARKit:
- **Plane Detection**: Automatic detection of horizontal and vertical surfaces
- **Scene Reconstruction**: 3D mesh of the environment
- **World Tracking**: 6DOF tracking of device position/orientation
- **Spatial Anchors**: Persistent locations in space

### What We Added (This Boilerplate)

We built on top of these capabilities:
- **Corner Detection**: Algorithmic detection of corners from plane boundaries
- **Plane Intersection Analysis**: Finding where planes meet (room corners, edges)
- **Visualization System**: Debug visualization of detected features
- **Game Integration**: Using spatial data for gameplay mechanics

## Architecture

### SpatialTrackingManager

**Location**: `Sources/Managers/SpatialTrackingManager.swift`

The central manager for all spatial tracking features.

#### Key Features:

1. **Plane Detection**
   - Detects horizontal planes (floors, tables, ceilings)
   - Detects vertical planes (walls, doors, windows)
   - Classifies planes by type
   - Tracks plane updates in real-time

2. **Corner Detection** (Two Methods)
   - **Boundary Corners**: Extracts vertices from plane boundaries
   - **Intersection Corners**: Calculates where planes intersect

3. **Real-time Updates**
   - Streams plane updates from ARKit
   - Continuously recalculates corners
   - Notifies game systems of changes

#### Usage Example:

```swift
let spatialManager = SpatialTrackingManager()

// Start tracking
await spatialManager.startTracking()

// Access detected features
let planes = spatialManager.detectedPlanes
let corners = spatialManager.detectedCorners

// Query functions
let nearestCorner = spatialManager.getNearestCorner(to: position)
let floors = spatialManager.getHorizontalPlanes()
```

## Corner Detection Algorithm

### Method 1: Plane Boundary Corners

```
1. ARKit provides plane boundaries as 2D polygons
2. Extract vertex positions from boundary
3. Transform 2D local coordinates to 3D world space
4. Each vertex is a potential corner
```

**Use Cases**:
- Edges of tables
- Boundaries of rugs/mats
- Edges of detected surfaces

### Method 2: Plane Intersection Corners

```
1. Take pairs of detected planes
2. Check if planes intersect (not parallel)
3. Calculate line of intersection
4. Find where intersection line meets plane boundaries
5. Those points are room corners
```

**Use Cases**:
- Wall-to-wall corners
- Wall-to-floor edges
- Ceiling-to-wall junctions

### Duplicate Removal

Corners within 5cm of each other are merged to avoid duplicates:

```swift
private func removeDuplicateCorners(_ corners: [DetectedCorner], threshold: Float) -> [DetectedCorner]
```

## Visualization System

**Location**: `Sources/Utilities/SpatialVisualizer.swift`

Creates 3D visualizations of detected spatial features.

### Features:

1. **Corner Markers**
   - Colored spheres at corner positions
   - Normal indicators showing orientation
   - Different colors for different types

2. **Plane Visualization**
   - Semi-transparent fills
   - Boundary outlines
   - Color-coded by classification

3. **Debug View**
   - Comprehensive visualization of all features
   - Room corner highlighting
   - Reference grids

### Usage Example:

```swift
// Visualize a single corner
let marker = SpatialVisualizer.createCornerMarker(
    for: corner,
    color: .blue,
    size: 0.05
)
rootEntity.addChild(marker)

// Visualize all spatial features
let debugViz = SpatialVisualizer.createDebugVisualization(
    planes: planes,
    corners: corners
)
rootEntity.addChild(debugViz)
```

## Game Integration

**Location**: `Sources/Extensions/GameManager+SpatialTracking.swift`

Integrates spatial tracking with game mechanics.

### Gameplay Applications:

#### 1. Player-Floor Snapping
```swift
private func snapPlayerToFloor(_ floor: DetectedPlane) {
    localPlayer.position.y = floor.center.y + GameConfig.playerSize
}
```

#### 2. Wall Collision
```swift
private func createWallCollider(_ wall: DetectedPlane) {
    // Creates invisible collision geometry
    // Prevents players from walking through walls
}
```

#### 3. Dynamic Spawn Points
```swift
func findDynamicSpawnPoints(manager: SpatialTrackingManager) -> [SIMD3<Float>] {
    // Uses detected corners as spawn locations
    // Ensures spawns are in valid positions
}
```

#### 4. Item Placement
```swift
private func spawnItemsOnSurface(_ surface: DetectedPlane) {
    // Spawns collectibles on detected tables/floors
}
```

## UI Controls

**Location**: `Sources/ContentView.swift`

User interface for spatial tracking features:

- **Start/Stop Tracking**: Enable/disable spatial understanding
- **Show/Hide Debug**: Toggle visualization
- **Spatial Status**: Real-time count of planes and corners
- **Visual Indicators**: Status of tracking system

## Permissions Required

Add to `Info.plist`:

```xml
<key>NSWorldSensingUsageDescription</key>
<string>This app uses world sensing to understand your environment for AR gameplay.</string>
```

The app automatically requests:
- `worldSensing` - Access to spatial mesh
- `planeDetection` - Detect surfaces
- `sceneReconstruction` - Detailed geometry (optional)

## Performance Considerations

### Optimization Strategies:

1. **Spatial Updates**: Corners recalculated only when planes change
2. **Duplicate Removal**: Prevents redundant corner markers
3. **Conditional Visualization**: Debug view only when enabled
4. **Efficient Queries**: Spatial indexing for nearest-neighbor searches

### Typical Performance:

- **Plane Detection**: 5-20 planes in typical room
- **Corner Detection**: 20-50 corners depending on complexity
- **Update Frequency**: As planes are discovered/updated
- **Frame Impact**: Minimal when visualization disabled

## Advanced Usage

### Custom Corner Analysis

```swift
// Find room corners (where 3+ planes meet)
let cornerGroups = groupNearbyCorners(corners, threshold: 0.15)
for group in cornerGroups where group.count >= 2 {
    // This is likely a room corner
    let roomCorner = group[0].position
}
```

### Spatial Queries

```swift
// Check if position is near wall
func isNearWall(position: SIMD3<Float>, threshold: Float = 0.3) -> Bool {
    let walls = manager.getVerticalPlanes().filter { $0.classification == .wall }
    // ... check distances
}

// Find nearest floor
func findNearestFloor(to position: SIMD3<Float>) -> DetectedPlane? {
    return manager.getHorizontalPlanes()
        .filter { $0.classification == .floor }
        .min { /* distance comparison */ }
}
```

### Line-Plane Intersection

The boilerplate includes math utilities for:
- Line-line intersection
- Closest point calculations
- Segment containment tests

```swift
private func closestPointBetweenLines(
    line1Start: SIMD3<Float>,
    line1Direction: SIMD3<Float>,
    line2Start: SIMD3<Float>,
    line2Direction: SIMD3<Float>
) -> SIMD3<Float>?
```

## Debugging

### Enable Debug Mode

In `GameConfig.swift`:
```swift
static let enableDebugMode = true
```

### Console Output

The system logs:
- Plane additions/removals with classification
- Corner count updates
- Spatial feature changes

Example output:
```
Spatial tracking started
Plane added: Floor at [0.0, 0.0, -2.0]
Updated corners: 12 detected
Plane added: Wall at [2.0, 1.5, -4.0]
Updated corners: 24 detected
```

### Visual Debug

Enable in UI or programmatically:
```swift
gameManager.toggleSpatialVisualization(enabled: true, manager: spatialManager)
```

Shows:
- Blue spheres: Boundary corners
- Green spheres: Intersection corners
- Red spheres: Room corners
- Yellow lines: Plane boundaries
- Colored fills: Plane surfaces

## Known Limitations

1. **Plane Geometry API**: Some visionOS APIs are still evolving; implementation may need updates
2. **Boundary Accuracy**: ARKit plane boundaries can be approximate
3. **Corner Precision**: Intersection calculations depend on plane accuracy
4. **Classification**: Not all surfaces get classified (some marked as "unknown")

## Future Enhancements

Potential improvements:
- [ ] Mesh-based corner detection (higher precision)
- [ ] Corner type classification (convex, concave, T-junction)
- [ ] Persistent anchors for corners
- [ ] Machine learning-enhanced recognition
- [ ] Semantic understanding (doorways, windows)

## Example Use Cases

### 1. Cover-Based Shooter
```swift
// Use corners for cover points
let coverPoints = spatialManager.getCornersNear(position: playerPos, radius: 5.0)
```

### 2. Physics-Based Game
```swift
// Use detected planes for realistic physics
for plane in spatialManager.detectedPlanes.values {
    createPhysicsCollider(for: plane)
}
```

### 3. Strategic Placement Game
```swift
// Place game objects only on detected surfaces
let validPlacements = spatialManager.getHorizontalPlanes()
    .filter { $0.classification == .table || $0.classification == .floor }
```

### 4. Hide and Seek
```swift
// Use room corners as hiding spots
let hidingSpots = findRoomCorners(from: spatialManager.detectedCorners)
```

## Testing

### Simulator Testing
- Limited plane detection in simulator
- Use synthetic planes for development
- Full testing requires physical device

### Real Device Testing
1. Start in well-lit room
2. Move device slowly to scan environment
3. Look at floors, walls, ceiling
4. Wait 5-10 seconds for initial detection
5. Check debug visualization

## References

- [ARKit Documentation](https://developer.apple.com/documentation/arkit)
- [PlaneDetection in visionOS](https://developer.apple.com/documentation/arkit/arkit_in_visionos)
- [RealityKit Visualization](https://developer.apple.com/documentation/realitykit)
- [World Tracking](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)

---

**Summary**: The spatial tracking system provides comprehensive access to Vision Pro's built-in spatial understanding, with added corner detection, visualization, and game integration. Perfect for AR games that need environmental awareness.
