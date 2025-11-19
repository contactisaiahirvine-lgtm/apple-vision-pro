import Foundation
import RealityKit
import Combine

/// Manages loading, caching, and lifecycle of 3D assets for AR placement
@MainActor
class AssetManager: ObservableObject {

    // MARK: - Published Properties

    @Published var availableAssets: [AssetDefinition] = []
    @Published var loadingAssets: Set<String> = []
    @Published var loadedAssets: [String: ModelEntity] = [:]

    // MARK: - Private Properties

    private var assetCache: [String: Entity] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        loadAssetLibrary()
        print("AssetManager initialized with \(availableAssets.count) assets")
    }

    // MARK: - Asset Library Loading

    private func loadAssetLibrary() {
        // Load built-in assets
        availableAssets = AssetLibrary.builtInAssets

        // Could extend to load from bundle, remote server, or user documents
    }

    // MARK: - Asset Loading

    /// Load a 3D asset asynchronously
    func loadAsset(named name: String) async throws -> Entity {
        // Check cache first
        if let cached = assetCache[name] {
            print("Loaded asset '\(name)' from cache")
            return cached.clone(recursive: true)
        }

        // Find asset definition
        guard let assetDef = availableAssets.first(where: { $0.id == name }) else {
            throw AssetError.assetNotFound(name)
        }

        // Mark as loading
        loadingAssets.insert(name)
        defer { loadingAssets.remove(name) }

        do {
            let entity = try await loadAssetFromSource(assetDef)

            // Cache the loaded asset
            assetCache[name] = entity

            print("Successfully loaded asset: \(name)")
            return entity.clone(recursive: true)

        } catch {
            print("Failed to load asset '\(name)': \(error)")
            throw error
        }
    }

    private func loadAssetFromSource(_ assetDef: AssetDefinition) async throws -> Entity {
        switch assetDef.source {
        case .bundle(let filename):
            return try await loadFromBundle(filename: filename, assetDef: assetDef)

        case .reality(let sceneName):
            return try await loadFromRealityFile(sceneName: sceneName)

        case .generated(let type):
            return try generateAsset(type: type, assetDef: assetDef)

        case .remote(let url):
            return try await loadFromURL(url: url, assetDef: assetDef)
        }
    }

    // MARK: - Loading Methods

    private func loadFromBundle(filename: String, assetDef: AssetDefinition) async throws -> Entity {
        // Load USDZ from bundle
        guard let url = Bundle.main.url(forResource: filename, withExtension: "usdz") else {
            throw AssetError.fileNotFound(filename)
        }

        let entity = try await Entity.load(contentsOf: url)

        // Apply asset properties
        applyAssetProperties(to: entity, from: assetDef)

        return entity
    }

    private func loadFromRealityFile(sceneName: String) async throws -> Entity {
        // Load from Reality Composer scene
        do {
            let scene = try await Entity.load(named: sceneName)
            return scene
        } catch {
            throw AssetError.loadFailed(sceneName, error)
        }
    }

    private func generateAsset(type: GeneratedAssetType, assetDef: AssetDefinition) throws -> Entity {
        let entity = ModelEntity()

        switch type {
        case .box(let size):
            entity.components.set(ModelComponent(
                mesh: .generateBox(size: size),
                materials: [SimpleMaterial(color: assetDef.previewColor, isMetallic: false)]
            ))

        case .sphere(let radius):
            entity.components.set(ModelComponent(
                mesh: .generateSphere(radius: radius),
                materials: [SimpleMaterial(color: assetDef.previewColor, isMetallic: false)]
            ))

        case .cylinder(let height, let radius):
            entity.components.set(ModelComponent(
                mesh: .generateCylinder(height: height, radius: radius),
                materials: [SimpleMaterial(color: assetDef.previewColor, isMetallic: false)]
            ))

        case .plane(let width, let height):
            entity.components.set(ModelComponent(
                mesh: .generatePlane(width: width, height: height),
                materials: [SimpleMaterial(color: assetDef.previewColor, isMetallic: false)]
            ))
        }

        // Apply properties
        applyAssetProperties(to: entity, from: assetDef)

        return entity
    }

    private func loadFromURL(url: URL, assetDef: AssetDefinition) async throws -> Entity {
        do {
            let entity = try await Entity.load(contentsOf: url)
            applyAssetProperties(to: entity, from: assetDef)
            return entity
        } catch {
            throw AssetError.downloadFailed(url, error)
        }
    }

    // MARK: - Asset Configuration

    private func applyAssetProperties(to entity: Entity, from assetDef: AssetDefinition) {
        // Set name
        entity.name = assetDef.id

        // Apply scale
        entity.scale = SIMD3<Float>(
            repeating: Float(assetDef.defaultScale)
        )

        // Add collision if needed
        if assetDef.hasCollision {
            addCollisionComponent(to: entity)
        }

        // Add physics if needed
        if assetDef.hasPhysics {
            addPhysicsComponent(to: entity)
        }

        // Make interactive
        entity.components.set(InputTargetComponent())
    }

    private func addCollisionComponent(to entity: Entity) {
        // Generate collision shape based on entity bounds
        if let modelEntity = entity as? ModelEntity {
            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let size = bounds.extents

            let shape = ShapeResource.generateBox(size: size)
            modelEntity.components.set(CollisionComponent(shapes: [shape]))
        }
    }

    private func addPhysicsComponent(to entity: Entity) {
        if let modelEntity = entity as? ModelEntity {
            // Add physics body
            let physicsMaterial = PhysicsMaterialResource.generate(
                friction: 0.5,
                restitution: 0.3
            )

            modelEntity.components.set(PhysicsBodyComponent(
                massProperties: .default,
                material: physicsMaterial,
                mode: .dynamic
            ))
        }
    }

    // MARK: - Asset Creation Helpers

    /// Create an instance of an asset for placement
    func createInstance(of assetName: String) async throws -> Entity {
        let entity = try await loadAsset(named: assetName)

        // Clone to create independent instance
        return entity.clone(recursive: true)
    }

    /// Preload commonly used assets
    func preloadAssets(_ assetNames: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for name in assetNames {
                group.addTask { [weak self] in
                    do {
                        _ = try await self?.loadAsset(named: name)
                        print("Preloaded asset: \(name)")
                    } catch {
                        print("Failed to preload asset '\(name)': \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Cache Management

    /// Clear asset cache to free memory
    func clearCache() {
        assetCache.removeAll()
        loadedAssets.removeAll()
        print("Asset cache cleared")
    }

    /// Remove specific asset from cache
    func removeFromCache(assetName: String) {
        assetCache.removeValue(forKey: assetName)
        loadedAssets.removeValue(forKey: assetName)
        print("Removed '\(assetName)' from cache")
    }

    /// Get cache size in bytes (approximate)
    var cacheSize: Int {
        // Approximate - would need more detailed tracking for accuracy
        return assetCache.count * 1024 * 100 // Rough estimate: 100KB per asset
    }
}

// MARK: - Asset Definition

struct AssetDefinition: Identifiable, Codable {
    let id: String
    let name: String
    let category: AssetCategory
    let source: AssetSource
    let previewColor: UIColor
    let defaultScale: Double
    let hasCollision: Bool
    let hasPhysics: Bool
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, category, source, defaultScale, hasCollision, hasPhysics, tags
        case previewColorR, previewColorG, previewColorB, previewColorA
    }

    init(id: String, name: String, category: AssetCategory, source: AssetSource,
         previewColor: UIColor = .blue, defaultScale: Double = 1.0,
         hasCollision: Bool = true, hasPhysics: Bool = false, tags: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.source = source
        self.previewColor = previewColor
        self.defaultScale = defaultScale
        self.hasCollision = hasCollision
        self.hasPhysics = hasPhysics
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(AssetCategory.self, forKey: .category)
        source = try container.decode(AssetSource.self, forKey: .source)
        defaultScale = try container.decode(Double.self, forKey: .defaultScale)
        hasCollision = try container.decode(Bool.self, forKey: .hasCollision)
        hasPhysics = try container.decode(Bool.self, forKey: .hasPhysics)
        tags = try container.decode([String].self, forKey: .tags)

        let r = try container.decode(CGFloat.self, forKey: .previewColorR)
        let g = try container.decode(CGFloat.self, forKey: .previewColorG)
        let b = try container.decode(CGFloat.self, forKey: .previewColorB)
        let a = try container.decode(CGFloat.self, forKey: .previewColorA)
        previewColor = UIColor(red: r, green: g, blue: b, alpha: a)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(source, forKey: .source)
        try container.encode(defaultScale, forKey: .defaultScale)
        try container.encode(hasCollision, forKey: .hasCollision)
        try container.encode(hasPhysics, forKey: .hasPhysics)
        try container.encode(tags, forKey: .tags)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        previewColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        try container.encode(r, forKey: .previewColorR)
        try container.encode(g, forKey: .previewColorG)
        try container.encode(b, forKey: .previewColorB)
        try container.encode(a, forKey: .previewColorA)
    }
}

enum AssetCategory: String, Codable, CaseIterable {
    case furniture = "Furniture"
    case decoration = "Decoration"
    case primitive = "Primitive"
    case character = "Character"
    case environment = "Environment"
    case game = "Game Objects"
    case custom = "Custom"
}

enum AssetSource: Codable, Equatable {
    case bundle(filename: String)
    case reality(sceneName: String)
    case generated(type: GeneratedAssetType)
    case remote(url: URL)

    enum CodingKeys: String, CodingKey {
        case type, filename, sceneName, generatedType, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "bundle":
            let filename = try container.decode(String.self, forKey: .filename)
            self = .bundle(filename: filename)
        case "reality":
            let sceneName = try container.decode(String.self, forKey: .sceneName)
            self = .reality(sceneName: sceneName)
        case "generated":
            let genType = try container.decode(GeneratedAssetType.self, forKey: .generatedType)
            self = .generated(type: genType)
        case "remote":
            let url = try container.decode(URL.self, forKey: .url)
            self = .remote(url: url)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown asset source type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .bundle(let filename):
            try container.encode("bundle", forKey: .type)
            try container.encode(filename, forKey: .filename)
        case .reality(let sceneName):
            try container.encode("reality", forKey: .type)
            try container.encode(sceneName, forKey: .sceneName)
        case .generated(let type):
            try container.encode("generated", forKey: .type)
            try container.encode(type, forKey: .generatedType)
        case .remote(let url):
            try container.encode("remote", forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}

enum GeneratedAssetType: Codable, Equatable {
    case box(size: SIMD3<Float>)
    case sphere(radius: Float)
    case cylinder(height: Float, radius: Float)
    case plane(width: Float, height: Float)

    enum CodingKeys: String, CodingKey {
        case type, sizeX, sizeY, sizeZ, radius, height, width
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "box":
            let x = try container.decode(Float.self, forKey: .sizeX)
            let y = try container.decode(Float.self, forKey: .sizeY)
            let z = try container.decode(Float.self, forKey: .sizeZ)
            self = .box(size: SIMD3(x, y, z))
        case "sphere":
            let r = try container.decode(Float.self, forKey: .radius)
            self = .sphere(radius: r)
        case "cylinder":
            let h = try container.decode(Float.self, forKey: .height)
            let r = try container.decode(Float.self, forKey: .radius)
            self = .cylinder(height: h, radius: r)
        case "plane":
            let w = try container.decode(Float.self, forKey: .width)
            let h = try container.decode(Float.self, forKey: .height)
            self = .plane(width: w, height: h)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown generated asset type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .box(let size):
            try container.encode("box", forKey: .type)
            try container.encode(size.x, forKey: .sizeX)
            try container.encode(size.y, forKey: .sizeY)
            try container.encode(size.z, forKey: .sizeZ)
        case .sphere(let radius):
            try container.encode("sphere", forKey: .type)
            try container.encode(radius, forKey: .radius)
        case .cylinder(let height, let radius):
            try container.encode("cylinder", forKey: .type)
            try container.encode(height, forKey: .height)
            try container.encode(radius, forKey: .radius)
        case .plane(let width, let height):
            try container.encode("plane", forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        }
    }
}

// MARK: - Errors

enum AssetError: LocalizedError {
    case assetNotFound(String)
    case fileNotFound(String)
    case loadFailed(String, Error)
    case downloadFailed(URL, Error)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let name):
            return "Asset '\(name)' not found in library"
        case .fileNotFound(let filename):
            return "File '\(filename)' not found in bundle"
        case .loadFailed(let name, let error):
            return "Failed to load '\(name)': \(error.localizedDescription)"
        case .downloadFailed(let url, let error):
            return "Failed to download from '\(url)': \(error.localizedDescription)"
        case .invalidFormat(let details):
            return "Invalid asset format: \(details)"
        }
    }
}

// MARK: - Asset Library

struct AssetLibrary {
    /// Built-in assets available in the app
    static let builtInAssets: [AssetDefinition] = [
        // Primitives
        AssetDefinition(
            id: "cube",
            name: "Cube",
            category: .primitive,
            source: .generated(type: .box(size: SIMD3(0.1, 0.1, 0.1))),
            previewColor: .systemBlue,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: true,
            tags: ["basic", "shape"]
        ),
        AssetDefinition(
            id: "sphere",
            name: "Sphere",
            category: .primitive,
            source: .generated(type: .sphere(radius: 0.05)),
            previewColor: .systemRed,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: true,
            tags: ["basic", "shape"]
        ),
        AssetDefinition(
            id: "cylinder",
            name: "Cylinder",
            category: .primitive,
            source: .generated(type: .cylinder(height: 0.15, radius: 0.05)),
            previewColor: .systemGreen,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: true,
            tags: ["basic", "shape"]
        ),
        AssetDefinition(
            id: "platform",
            name: "Platform",
            category: .game,
            source: .generated(type: .box(size: SIMD3(0.3, 0.02, 0.3))),
            previewColor: .systemGray,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: false,
            tags: ["game", "platform"]
        ),

        // Decorative items
        AssetDefinition(
            id: "marker",
            name: "Marker",
            category: .decoration,
            source: .generated(type: .sphere(radius: 0.02)),
            previewColor: .systemYellow,
            defaultScale: 1.0,
            hasCollision: false,
            hasPhysics: false,
            tags: ["marker", "point"]
        ),
        AssetDefinition(
            id: "wall",
            name: "Wall",
            category: .environment,
            source: .generated(type: .box(size: SIMD3(0.5, 1.0, 0.05))),
            previewColor: .systemGray2,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: false,
            tags: ["environment", "structure"]
        ),

        // Game objects
        AssetDefinition(
            id: "target",
            name: "Target",
            category: .game,
            source: .generated(type: .box(size: SIMD3(0.2, 0.2, 0.05))),
            previewColor: .systemOrange,
            defaultScale: 1.0,
            hasCollision: true,
            hasPhysics: false,
            tags: ["game", "interactive"]
        ),
        AssetDefinition(
            id: "spawn_point",
            name: "Spawn Point",
            category: .game,
            source: .generated(type: .cylinder(height: 0.1, radius: 0.15)),
            previewColor: .systemPurple,
            defaultScale: 1.0,
            hasCollision: false,
            hasPhysics: false,
            tags: ["game", "spawn"]
        )
    ]
}
