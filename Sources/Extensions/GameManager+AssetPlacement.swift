import Foundation
import Combine
import ObjectiveC

extension GameManager {
    // MARK: - Associated Properties

    var placementManager: PlacementManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.placementManager) as? PlacementManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.placementManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var assetManager: AssetManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.assetManager) as? AssetManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.assetManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var anchorManager: AnchorManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.anchorManager) as? AnchorManager
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.anchorManager, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Setup

    func setupAssetPlacement() {
        guard placementManager == nil else { return }

        let assetMgr = AssetManager()
        let anchorMgr = AnchorManager()
        let placementMgr = PlacementManager()

        assetManager = assetMgr
        anchorManager = anchorMgr
        placementManager = placementMgr

        // Setup listeners for placement events
        setupPlacementListeners()

        print("Asset placement system initialized")
    }

    private func setupPlacementListeners() {
        // Listen for object placement
        NotificationCenter.default.publisher(for: .objectPlaced)
            .sink { [weak self] notification in
                guard let object = notification.userInfo?["object"] as? PlacedObject else { return }
                self?.broadcastObjectPlacement(object)
            }
            .store(in: &cancellables)

        // Listen for object movement
        NotificationCenter.default.publisher(for: .objectMoved)
            .sink { [weak self] notification in
                guard let object = notification.userInfo?["object"] as? PlacedObject,
                      let position = notification.userInfo?["position"] as? SIMD3<Float> else { return }
                self?.broadcastObjectMove(objectID: object.id, position: position)
            }
            .store(in: &cancellables)

        // Listen for object rotation
        NotificationCenter.default.publisher(for: .objectRotated)
            .sink { [weak self] notification in
                guard let object = notification.userInfo?["object"] as? PlacedObject,
                      let rotation = notification.userInfo?["rotation"] as? simd_quatf else { return }
                self?.broadcastObjectRotation(objectID: object.id, rotation: rotation)
            }
            .store(in: &cancellables)

        // Listen for object deletion
        NotificationCenter.default.publisher(for: .objectDeleted)
            .sink { [weak self] notification in
                guard let objectID = notification.userInfo?["objectID"] as? UInt32 else { return }
                self?.broadcastObjectDeletion(objectID: objectID)
            }
            .store(in: &cancellables)

        // Listen for remote placement events
        NotificationCenter.default.publisher(for: .remotePlacementReceived)
            .sink { [weak self] notification in
                guard let data = notification.userInfo?["data"] as? Data else { return }
                self?.handleRemotePlacement(data)
            }
            .store(in: &cancellables)
    }

    // MARK: - Network Broadcasting

    private func broadcastObjectPlacement(_ object: PlacedObject) {
        let data = PlacementNetworkData(
            type: .placed,
            objectID: object.id,
            assetName: object.assetName,
            position: object.position,
            rotation: object.rotation,
            scale: object.scale
        )

        guard let encoded = try? JSONEncoder().encode(data) else {
            print("Failed to encode placement data")
            return
        }

        let message = NetworkMessage.gameEvent(encoded)

        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )

        print("Broadcast object placement: \(object.assetName)")
    }

    private func broadcastObjectMove(objectID: UInt32, position: SIMD3<Float>) {
        let data = PlacementNetworkData(
            type: .moved,
            objectID: objectID,
            assetName: "",
            position: position,
            rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
            scale: SIMD3(repeating: 1.0)
        )

        guard let encoded = try? JSONEncoder().encode(data) else { return }

        let message = NetworkMessage.gameEvent(encoded)

        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )
    }

    private func broadcastObjectRotation(objectID: UInt32, rotation: simd_quatf) {
        let data = PlacementNetworkData(
            type: .rotated,
            objectID: objectID,
            assetName: "",
            position: SIMD3(0, 0, 0),
            rotation: rotation,
            scale: SIMD3(repeating: 1.0)
        )

        guard let encoded = try? JSONEncoder().encode(data) else { return }

        let message = NetworkMessage.gameEvent(encoded)

        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )
    }

    private func broadcastObjectDeletion(objectID: UInt32) {
        let data = PlacementNetworkData(
            type: .deleted,
            objectID: objectID,
            assetName: "",
            position: SIMD3(0, 0, 0),
            rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
            scale: SIMD3(repeating: 1.0)
        )

        guard let encoded = try? JSONEncoder().encode(data) else { return }

        let message = NetworkMessage.gameEvent(encoded)

        NotificationCenter.default.post(
            name: .sendNetworkMessage,
            object: nil,
            userInfo: ["message": message]
        )

        print("Broadcast object deletion: \(objectID)")
    }

    // MARK: - Remote Event Handling

    private func handleRemotePlacement(_ data: Data) {
        guard let placementData = try? JSONDecoder().decode(PlacementNetworkData.self, from: data) else {
            print("Failed to decode remote placement data")
            return
        }

        Task { @MainActor in
            await handlePlacementData(placementData)
        }
    }

    private func handlePlacementData(_ data: PlacementNetworkData) async {
        guard let placementMgr = placementManager,
              let assetMgr = assetManager,
              let anchorMgr = anchorManager else {
            return
        }

        switch data.type {
        case .placed:
            // Create object from remote placement
            do {
                let entity = try await assetMgr.createInstance(of: data.assetName)

                entity.position = data.position
                entity.orientation = data.rotation
                entity.scale = data.scale

                let anchor = try await anchorMgr.createWorldAnchor(at: data.position)
                anchor.addChild(entity)

                // Add to placed objects (without broadcasting again)
                let placedObject = PlacedObject(
                    id: data.objectID,
                    assetName: data.assetName,
                    position: data.position,
                    rotation: data.rotation,
                    scale: data.scale,
                    anchor: anchor,
                    entity: entity
                )

                placementMgr.placedObjects.append(placedObject)

                print("Placed remote object: \(data.assetName)")

            } catch {
                print("Failed to place remote object: \(error)")
            }

        case .moved:
            // Update object position
            if let object = placementMgr.placedObjects.first(where: { $0.id == data.objectID }) {
                placementMgr.moveObject(object, to: data.position)
            }

        case .rotated:
            // Update object rotation
            if let object = placementMgr.placedObjects.first(where: { $0.id == data.objectID }) {
                object.entity.orientation = data.rotation
                object.rotation = data.rotation
            }

        case .deleted:
            // Delete object
            if let object = placementMgr.placedObjects.first(where: { $0.id == data.objectID }) {
                placementMgr.deleteObject(object)
            }
        }
    }

    // MARK: - Convenience Methods

    func placeAsset(_ assetName: String, at position: SIMD3<Float>) async throws {
        guard let assetMgr = assetManager,
              let anchorMgr = anchorManager,
              let placementMgr = placementManager else {
            throw PlacementError.managersNotInitialized
        }

        let entity = try await assetMgr.createInstance(of: assetName)
        let anchor = try await anchorMgr.createWorldAnchor(at: position)

        anchor.addChild(entity)

        let placedObject = PlacedObject(
            id: placementMgr.placedObjects.count > 0 ? placementMgr.placedObjects.map { $0.id }.max()! + 1 : 1,
            assetName: assetName,
            position: position,
            rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
            scale: SIMD3(repeating: 1.0),
            anchor: anchor,
            entity: entity
        )

        placementMgr.placedObjects.append(placedObject)

        // Notify placement
        NotificationCenter.default.post(
            name: .objectPlaced,
            object: nil,
            userInfo: ["object": placedObject]
        )
    }
}

// MARK: - Associated Keys Extension

private extension AssociatedKeys {
    static var placementManager = "placementManager"
    static var assetManager = "assetManager"
    static var anchorManager = "anchorManager"
}

// MARK: - Placement Network Data

struct PlacementNetworkData: Codable {
    enum PlacementEventType: String, Codable {
        case placed, moved, rotated, scaled, deleted
    }

    let type: PlacementEventType
    let objectID: UInt32
    let assetName: String
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>

    enum CodingKeys: String, CodingKey {
        case type, objectID, assetName
        case posX, posY, posZ
        case rotX, rotY, rotZ, rotW
        case scaleX, scaleY, scaleZ
    }

    init(type: PlacementEventType, objectID: UInt32, assetName: String,
         position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        self.type = type
        self.objectID = objectID
        self.assetName = assetName
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decode(PlacementEventType.self, forKey: .type)
        objectID = try container.decode(UInt32.self, forKey: .objectID)
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

        try container.encode(type, forKey: .type)
        try container.encode(objectID, forKey: .objectID)
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

// MARK: - Placement Error

enum PlacementError: LocalizedError {
    case managersNotInitialized
    case assetNotFound
    case anchorCreationFailed

    var errorDescription: String? {
        switch self {
        case .managersNotInitialized:
            return "Placement managers not initialized"
        case .assetNotFound:
            return "Asset not found in library"
        case .anchorCreationFailed:
            return "Failed to create world anchor"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let remotePlacementReceived = Notification.Name("remotePlacementReceived")
}
