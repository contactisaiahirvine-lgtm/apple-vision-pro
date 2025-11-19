Guidelines for a Vision Pro–Specific AR Game Engine
1. Core Engine Architecture
A modular engine structure should include:
- Core runtime (application, loop, events)
- Platform layer for visionOS (Swift bridging)
- Graphics (Metal renderer, shaders, render graph)
- AR subsystem (spatial mapping, anchors)
- Input (gaze, gestures)
- ECS (components, systems)
- Physics
- Audio (spatial audio)
- Build scripts/toolchain
2. Platform Layer for visionOS
Use RealityKit and ARKit for spatial tracking and passthrough. Use Swift for platform code and C++ for
the engine core. Bridge with C interfaces. Include ImmersiveSpace entry point and data conversion
between Swift and C++.
3. Rendering System
Requirements:
- Stereoscopic rendering with per-eye matrices
- Passthrough compositing
- Metal integration with RealityKit
- Depth integration using device-provided depth textures
- Foveation and dynamic resolution support
4. AR Subsystem
Must include:
- Plane detection, mesh reconstruction, spatial anchors
- Persistence and dynamic anchors
- Hit-testing for placement
- Maintain internal spatial map and update ECS components accordingly
5. Interaction Layer
Implement:
- Gaze tracking and raycasting
- Gesture handling (pinch, pinch+hold)
- Physics-based cursor for user feedback
- Event routing into ECS
6. ECS System
Use ECS to separate data from logic and allow modular systems:
- Components: Transform, Mesh, Anchor, PhysicsBody, InteractionTarget
- Systems: Rendering, AR updates, Physics, Input
- Central runtime loop calling system updates
7. Physics
Use a lightweight physics engine such as Bullet or PhysX. Sync physics bodies with AR anchors and
world transforms.
8. Asset Pipeline
Support USD/USDZ as primary formats. Convert glTF/KTX2 into USDZ during build. Provide pipeline
scripts for asset conversion.
9. Toolchain and Build System
Use CMake or custom scripts to compile the C++ engine into a static library. Link with Swift visionOS
project. Ensure Metal shader build pipeline and Xcode packaging.
10. Container, Scene, and Game Loop
Run the engine update inside RealityKit callbacks. Use ECS for logic and optionally a scene graph for
transform hierarchy. Maintain dual-eye camera system.
11. Debugging and Testing
Implement:
- Mock AR room environments
- macOS simulation for basic tests
- On-device testing for spatial accuracy