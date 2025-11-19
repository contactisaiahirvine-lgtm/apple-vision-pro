import Foundation
import RealityKit
import ARKit
import Combine

/// Manages placement of 3D assets in the AR world with proper anchoring
@MainActor
class PlacementManager: ObservableObject {

    // MARK: - Published Properties

    @Published var placedObjects: [PlacedObject] = []
    @Published var selectedObject: PlacedObject?
    @Published var placementMode: PlacementMode = .none
    @Published var previewEntity: Entity?

    // MARK: - Private Properties

    private var anchorManager: AnchorManager?
    private var assetManager: AssetManager?
    private weak var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    private var nextObjectID: UInt32 = 1

    // MARK: - Initialization

    init() {
        print("PlacementManager initialized")
    }

    func setup(arView: ARView, anchorManager: AnchorManager, assetManager: AssetManager) {
        self.arView = arView
        self.anchorManager = anchorManager
        self.assetManager = assetManager

        setupGestureRecognizers()
    }

    // MARK: - Gesture Setup

    private func setupGestureRecognizers() {
        guard let arView = arView else { return }

        // Tap gesture for placement
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // Long press for selection
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        arView.addGestureRecognizer(longPress)

        print("Gesture recognizers configured")
    }

    // MARK: - Placement Mode

    func startPlacement(assetName: String) async {
        guard let assetManager = assetManager else { return }

        placementMode = .placing(assetName: assetName)

        // Create preview entity
        do {
            let entity = try await assetManager.createInstance(of: assetName)

            // Make semi-transparent for preview
            makeEntitySemiTransparent(entity, opacity: 0.5)

            previewEntity = entity
            print("Started placement mode for '\(assetName)'")

        } catch {
            print("Failed to create preview for '\(assetName)': \(error)")
            placementMode = .none
        }
    }

    func cancelPlacement() {
        placementMode = .none
        previewEntity?.removeFromParent()
        previewEntity = nil
        print("Placement cancelled")
    }

    // MARK: - Object Placement

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        Task {
            await handleTapAsync(at: gesture.location(in: gesture.view))
        }
    }

    private func handleTapAsync(at location: CGPoint) async {
        guard let arView = arView else { return }

        switch placementMode {
        case .placing(let assetName):
            await placeObject(assetName: assetName, at: location)

        case .none:
            // Select object if tapped
            selectObjectAt(location: location)
        }
    }

    private func placeObject(assetName: String, at screenLocation: CGPoint) async {
        guard let arView = arView,
              let assetManager = assetManager,
              let anchorManager = anchorManager else {
            return
        }

        // Perform raycast to find placement location
        let results = arView.raycast(
            from: screenLocation,
            allowing: .estimatedPlane,
            alignment: .any
        )

        guard let firstResult = results.first else {
            print("No surface found for placement")
            return
        }

        // Create entity instance
        do {
            let entity = try await assetManager.createInstance(of: assetName)

            // Set position from raycast
            let position = SIMD3<Float>(
                firstResult.worldTransform.columns.3.x,
                firstResult.worldTransform.columns.3.y,
                firstResult.worldTransform.columns.3.z
            )

            // Create anchor
            let anchor = try await anchorManager.createWorldAnchor(at: position)

            // Attach entity to anchor
            anchor.addChild(entity)

            // Add to scene
            arView.scene.addAnchor(anchor)

            // Create placed object record
            let placedObject = PlacedObject(
                id: nextObjectID,
                assetName: assetName,
                position: position,
                rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                scale: SIMD3(repeating: 1.0),
                anchor: anchor,
                entity: entity
            )

            nextObjectID += 1
            placedObjects.append(placedObject)

            // Notify about placement
            NotificationCenter.default.post(
                name: .objectPlaced,
                object: nil,
                userInfo: ["object": placedObject]
            )

            print("Placed '\(assetName)' at \(position)")

        } catch {
            print("Failed to place object: \(error)")
        }
    }

    // MARK: - Object Selection

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let location = gesture.location(in: gesture.view)
        selectObjectAt(location: location)
    }

    private func selectObjectAt(location: CGPoint) {
        guard let arView = arView else { return }

        // Perform entity query
        let hitEntities = arView.entities(at: location)

        // Find first placed object
        for entity in hitEntities {
            if let placedObject = placedObjects.first(where: { $0.entity === entity }) {
                selectedObject = placedObject
                highlightSelectedObject()
                print("Selected object: \(placedObject.assetName)")
                return
            }
        }

        // Deselect if nothing hit
        selectedObject = nil
        removeHighlight()
    }

    private func highlightSelectedObject() {
        guard let selected = selectedObject,
              let modelEntity = selected.entity as? ModelEntity else {
            return
        }

        // Add highlight material
        var material = SimpleMaterial()
        material.color = .init(tint: .yellow.withAlphaComponent(0.3))
        modelEntity.model?.materials = [material]
    }

    private func removeHighlight() {
        // Restore original materials (would need to cache these)
    }

    // MARK: - Object Manipulation

    func moveObject(_ object: PlacedObject, to position: SIMD3<Float>) {
        guard let index = placedObjects.firstIndex(where: { $0.id == object.id }) else {
            return
        }

        // Update position
        object.entity.position = position
        placedObjects[index].position = position

        // Notify about update
        NotificationCenter.default.post(
            name: .objectMoved,
            object: nil,
            userInfo: ["object": object, "position": position]
        )

        print("Moved object \(object.id) to \(position)")
    }

    func rotateObject(_ object: PlacedObject, by angle: Float) {
        guard let index = placedObjects.firstIndex(where: { $0.id == object.id }) else {
            return
        }

        // Apply rotation
        let rotation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        object.entity.orientation = rotation * object.entity.orientation
        placedObjects[index].rotation = object.entity.orientation

        // Notify about update
        NotificationCenter.default.post(
            name: .objectRotated,
            object: nil,
            userInfo: ["object": object, "rotation": rotation]
        )

        print("Rotated object \(object.id)")
    }

    func scaleObject(_ object: PlacedObject, by factor: Float) {
        guard let index = placedObjects.firstIndex(where: { $0.id == object.id }) else {
            return
        }

        // Apply scale
        let newScale = object.scale * factor
        object.entity.scale = newScale
        placedObjects[index].scale = newScale

        // Notify about update
        NotificationCenter.default.post(
            name: .objectScaled,
            object: nil,
            userInfo: ["object": object, "scale": newScale]
        )

        print("Scaled object \(object.id) by \(factor)")
    }

    func deleteObject(_ object: PlacedObject) {
        guard let index = placedObjects.firstIndex(where: { $0.id == object.id }) else {
            return
        }

        // Remove from scene
        object.entity.removeFromParent()
        object.anchor.removeFromParent()

        // Remove from list
        placedObjects.remove(at: index)

        // Clear selection if this was selected
        if selectedObject?.id == object.id {
            selectedObject = nil
        }

        // Notify about deletion
        NotificationCenter.default.post(
            name: .objectDeleted,
            object: nil,
            userInfo: ["objectID": object.id]
        )

        print("Deleted object \(object.id)")
    }

    // MARK: - Placement Helpers

    /// Update preview entity position as user moves device
    func updatePreviewPosition(raycastResult: ARRaycastResult) {
        guard let preview = previewEntity else { return }

        let position = SIMD3<Float>(
            raycastResult.worldTransform.columns.3.x,
            raycastResult.worldTransform.columns.3.y,
            raycastResult.worldTransform.columns.3.z
        )

        preview.position = position
    }

    private func makeEntitySemiTransparent(_ entity: Entity, opacity: Float) {
        entity.visit { child in
            if var modelEntity = child as? ModelEntity,
               let model = modelEntity.model {
                var materials: [Material] = []

                for material in model.materials {
                    if var simpleMaterial = material as? SimpleMaterial {
                        simpleMaterial.color.tint = simpleMaterial.color.tint.withAlphaComponent(CGFloat(opacity))
                        materials.append(simpleMaterial)
                    } else {
                        materials.append(material)
                    }
                }

                modelEntity.model?.materials = materials
            }
        }
    }

    // MARK: - Scene Management

    func clearAll() {
        for object in placedObjects {
            object.entity.removeFromParent()
            object.anchor.removeFromParent()
        }

        placedObjects.removeAll()
        selectedObject = nil

        print("Cleared all placed objects")
    }

    // MARK: - Persistence

    func saveScene() -> PlacementScene {
        let objects = placedObjects.map { obj in
            PlacementScene.ObjectData(
                id: obj.id,
                assetName: obj.assetName,
                position: obj.position,
                rotation: obj.rotation,
                scale: obj.scale
            )
        }

        return PlacementScene(objects: objects)
    }

    func loadScene(_ scene: PlacementScene) async {
        guard let assetManager = assetManager,
              let anchorManager = anchorManager,
              let arView = arView else {
            return
        }

        // Clear existing
        clearAll()

        // Load each object
        for objectData in scene.objects {
            do {
                let entity = try await assetManager.createInstance(of: objectData.assetName)

                // Apply transforms
                entity.position = objectData.position
                entity.orientation = objectData.rotation
                entity.scale = objectData.scale

                // Create anchor
                let anchor = try await anchorManager.createWorldAnchor(at: objectData.position)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)

                // Create placed object record
                let placedObject = PlacedObject(
                    id: objectData.id,
                    assetName: objectData.assetName,
                    position: objectData.position,
                    rotation: objectData.rotation,
                    scale: objectData.scale,
                    anchor: anchor,
                    entity: entity
                )

                placedObjects.append(placedObject)

                // Update next ID
                if objectData.id >= nextObjectID {
                    nextObjectID = objectData.id + 1
                }

            } catch {
                print("Failed to load object '\(objectData.assetName)': \(error)")
            }
        }

        print("Loaded scene with \(scene.objects.count) objects")
    }
}

// MARK: - Placed Object

class PlacedObject: Identifiable, ObservableObject {
    let id: UInt32
    let assetName: String
    @Published var position: SIMD3<Float>
    @Published var rotation: simd_quatf
    @Published var scale: SIMD3<Float>

    let anchor: AnchorEntity
    let entity: Entity

    init(id: UInt32, assetName: String, position: SIMD3<Float>,
         rotation: simd_quatf, scale: SIMD3<Float>,
         anchor: AnchorEntity, entity: Entity) {
        self.id = id
        self.assetName = assetName
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.anchor = anchor
        self.entity = entity
    }
}

// MARK: - Placement Mode

enum PlacementMode: Equatable {
    case none
    case placing(assetName: String)
}

// MARK: - Scene Persistence

struct PlacementScene: Codable {
    let objects: [ObjectData]

    struct ObjectData: Codable {
        let id: UInt32
        let assetName: String
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let scale: SIMD3<Float>

        enum CodingKeys: String, CodingKey {
            case id, assetName
            case posX, posY, posZ
            case rotX, rotY, rotZ, rotW
            case scaleX, scaleY, scaleZ
        }

        init(id: UInt32, assetName: String, position: SIMD3<Float>,
             rotation: simd_quatf, scale: SIMD3<Float>) {
            self.id = id
            self.assetName = assetName
            self.position = position
            self.rotation = rotation
            self.scale = scale
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UInt32.self, forKey: .id)
            assetName = try container.decode(String.self, forKey: .assetName)

            let posX = try container.decode(Float.self, forKey: .posX)
            let posY = try container.decode(Float.self, forKey: .posY)
            let posZ = try container.decode(Float.self, forKey: .posZ)
            position = SIMD3(posX, posY, posZ)

            let rotX = try container.decode(Float.self, forKey: .rotX)
            let rotY = try container.decode(Float.self, forKey: .rotY)
            let rotZ = try container.decode(Float.self, forKey: .rotZ)
            let rotW = try container.decode(Float.self, forKey: .rotW)
            rotation = simd_quatf(ix: rotX, iy: rotY, iz: rotZ, r: rotW)

            let scaleX = try container.decode(Float.self, forKey: .scaleX)
            let scaleY = try container.decode(Float.self, forKey: .scaleY)
            let scaleZ = try container.decode(Float.self, forKey: .scaleZ)
            scale = SIMD3(scaleX, scaleY, scaleZ)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(assetName, forKey: .assetName)

            try container.encode(position.x, forKey: .posX)
            try container.encode(position.y, forKey: .posY)
            try container.encode(position.z, forKey: .posZ)

            try container.encode(rotation.vector.x, forKey: .rotX)
            try container.encode(rotation.vector.y, forKey: .rotY)
            try container.encode(rotation.vector.z, forKey: .rotZ)
            try container.encode(rotation.vector.w, forKey: .rotW)

            try container.encode(scale.x, forKey: .scaleX)
            try container.encode(scale.y, forKey: .scaleY)
            try container.encode(scale.z, forKey: .scaleZ)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let objectPlaced = Notification.Name("objectPlaced")
    static let objectMoved = Notification.Name("objectMoved")
    static let objectRotated = Notification.Name("objectRotated")
    static let objectScaled = Notification.Name("objectScaled")
    static let objectDeleted = Notification.Name("objectDeleted")
}
