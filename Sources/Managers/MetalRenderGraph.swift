import Foundation
import Metal
import MetalKit
import simd

/// Manages a dependency graph of rendering passes with automatic resource lifetime management
@MainActor
class MetalRenderGraph {

    // MARK: - Types

    typealias PassID = UUID

    enum ResourceType {
        case texture(MTLPixelFormat, Int, Int)  // format, width, height
        case buffer(Int)  // size in bytes
    }

    enum PassType {
        case graphics
        case compute
        case blit
    }

    struct RenderPass {
        let id: PassID
        let name: String
        let type: PassType
        let execute: (MTLCommandBuffer) -> Void
        var dependencies: [PassID] = []
        var reads: Set<String> = []  // Resource names
        var writes: Set<String> = []
    }

    struct Resource {
        let name: String
        let type: ResourceType
        var texture: MTLTexture?
        var buffer: MTLBuffer?
        var lastWritePass: PassID?
        var readers: Set<PassID> = []
    }

    // MARK: - Properties

    private weak var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?

    private var passes: [PassID: RenderPass] = [:]
    private var resources: [String: Resource] = [:]
    private var executionOrder: [PassID] = []
    private var isCompiled = false

    // MARK: - Statistics

    private(set) var totalPasses: Int = 0
    private(set) var totalResources: Int = 0
    private(set) var culledPasses: Int = 0
    private(set) var resourcesReused: Int = 0

    // MARK: - Initialization

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        print("✅ Metal Render Graph initialized")
    }

    // MARK: - Graph Building

    /// Add a rendering pass to the graph
    func addPass(
        name: String,
        type: PassType = .graphics,
        reads: [String] = [],
        writes: [String] = [],
        execute: @escaping (MTLCommandBuffer) -> Void
    ) -> PassID {
        let id = UUID()

        let pass = RenderPass(
            id: id,
            name: name,
            type: type,
            execute: execute,
            dependencies: [],
            reads: Set(reads),
            writes: Set(writes)
        )

        passes[id] = pass
        totalPasses += 1
        isCompiled = false

        print("Added render pass: \(name) (reads: \(reads.count), writes: \(writes.count))")
        return id
    }

    /// Declare a transient resource
    func declareResource(name: String, type: ResourceType) {
        guard resources[name] == nil else {
            print("WARNING: Resource '\(name)' already declared")
            return
        }

        var resource = Resource(name: name, type: type)

        // Create actual Metal resource
        switch type {
        case .texture(let format, let width, let height):
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            resource.texture = device?.makeTexture(descriptor: descriptor)

        case .buffer(let size):
            resource.buffer = device?.makeBuffer(length: size, options: .storageModePrivate)
        }

        resources[name] = resource
        totalResources += 1

        print("Declared resource: \(name)")
    }

    /// Set external texture (not managed by graph)
    func setExternalTexture(_ texture: MTLTexture, for name: String) {
        if resources[name] == nil {
            var resource = Resource(name: name, type: .texture(texture.pixelFormat, texture.width, texture.height))
            resource.texture = texture
            resources[name] = resource
        } else {
            resources[name]?.texture = texture
        }
    }

    /// Set external buffer (not managed by graph)
    func setExternalBuffer(_ buffer: MTLBuffer, for name: String) {
        if resources[name] == nil {
            var resource = Resource(name: name, type: .buffer(buffer.length))
            resource.buffer = buffer
            resources[name] = resource
        } else {
            resources[name]?.buffer = buffer
        }
    }

    // MARK: - Graph Compilation

    /// Compile the render graph - resolve dependencies and execution order
    func compile() {
        print("Compiling render graph...")

        // Build dependency graph
        buildDependencies()

        // Topological sort to determine execution order
        executionOrder = topologicalSort()

        // Cull unused passes
        cullUnusedPasses()

        // Optimize resource lifetimes
        optimizeResourceLifetimes()

        isCompiled = true
        print("✅ Render graph compiled: \(executionOrder.count) passes, \(resources.count) resources")
    }

    private func buildDependencies() {
        // For each pass, find passes it depends on (those that write what it reads)
        for (passID, pass) in passes {
            var deps: [PassID] = []

            for readResource in pass.reads {
                if let resource = resources[readResource],
                   let writerPass = resource.lastWritePass,
                   writerPass != passID {
                    deps.append(writerPass)
                }
            }

            passes[passID]?.dependencies = deps

            // Update resource tracking
            for writeResource in pass.writes {
                resources[writeResource]?.lastWritePass = passID
            }

            for readResource in pass.reads {
                resources[readResource]?.readers.insert(passID)
            }
        }
    }

    private func topologicalSort() -> [PassID] {
        var sorted: [PassID] = []
        var visited: Set<PassID> = []
        var visiting: Set<PassID> = []

        func visit(_ passID: PassID) {
            if visited.contains(passID) { return }
            if visiting.contains(passID) {
                print("ERROR: Circular dependency detected in render graph")
                return
            }

            visiting.insert(passID)

            if let pass = passes[passID] {
                for dep in pass.dependencies {
                    visit(dep)
                }
            }

            visiting.remove(passID)
            visited.insert(passID)
            sorted.append(passID)
        }

        for passID in passes.keys {
            visit(passID)
        }

        return sorted
    }

    private func cullUnusedPasses() {
        // Mark passes that contribute to final output
        // For now, keep all passes - would need to know which resources are "output"
        culledPasses = 0
    }

    private func optimizeResourceLifetimes() {
        // Track when resources can be released and reused
        // This would analyze the execution order and reuse texture memory
        resourcesReused = 0
    }

    // MARK: - Execution

    /// Execute the compiled render graph
    func execute() {
        guard isCompiled else {
            print("ERROR: Render graph not compiled. Call compile() first.")
            return
        }

        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            print("ERROR: Failed to create command buffer")
            return
        }

        commandBuffer.label = "RenderGraph"

        // Execute passes in dependency order
        for passID in executionOrder {
            guard let pass = passes[passID] else { continue }

            // Verify resources exist
            var resourcesValid = true
            for resourceName in pass.reads.union(pass.writes) {
                if resources[resourceName] == nil {
                    print("ERROR: Pass '\(pass.name)' references undefined resource '\(resourceName)'")
                    resourcesValid = false
                }
            }

            if resourcesValid {
                pass.execute(commandBuffer)
            }
        }

        commandBuffer.commit()
    }

    /// Execute with completion handler
    func execute(completion: @escaping () -> Void) {
        guard isCompiled else {
            print("ERROR: Render graph not compiled")
            return
        }

        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            print("ERROR: Failed to create command buffer")
            return
        }

        commandBuffer.label = "RenderGraph"

        for passID in executionOrder {
            guard let pass = passes[passID] else { continue }
            pass.execute(commandBuffer)
        }

        commandBuffer.addCompletedHandler { _ in
            Task { @MainActor in
                completion()
            }
        }

        commandBuffer.commit()
    }

    // MARK: - Resource Access

    /// Get texture for resource name
    func getTexture(_ name: String) -> MTLTexture? {
        return resources[name]?.texture
    }

    /// Get buffer for resource name
    func getBuffer(_ name: String) -> MTLBuffer? {
        return resources[name]?.buffer
    }

    // MARK: - Control

    /// Clear all passes and resources
    func reset() {
        passes.removeAll()
        resources.removeAll()
        executionOrder.removeAll()
        isCompiled = false
        totalPasses = 0
        totalResources = 0
        culledPasses = 0
        resourcesReused = 0
        print("Render graph reset")
    }

    /// Remove specific pass
    func removePass(_ id: PassID) {
        passes.removeValue(forKey: id)
        isCompiled = false
    }

    // MARK: - Debugging

    func printGraph() {
        print("\n=== Render Graph ===")
        print("Passes: \(passes.count)")
        print("Resources: \(resources.count)")
        print("Execution order:")

        for (index, passID) in executionOrder.enumerated() {
            if let pass = passes[passID] {
                print("  \(index + 1). \(pass.name)")
                if !pass.reads.isEmpty {
                    print("     Reads: \(pass.reads.joined(separator: ", "))")
                }
                if !pass.writes.isEmpty {
                    print("     Writes: \(pass.writes.joined(separator: ", "))")
                }
            }
        }

        print("\nResources:")
        for (name, resource) in resources {
            var info = "  \(name): "
            switch resource.type {
            case .texture(let format, let width, let height):
                info += "Texture(\(width)x\(height), \(format))"
            case .buffer(let size):
                info += "Buffer(\(size) bytes)"
            }
            if let writer = resource.lastWritePass,
               let pass = passes[writer] {
                info += " - written by '\(pass.name)'"
            }
            info += " - read by \(resource.readers.count) passes"
            print(info)
        }

        print("===================\n")
    }

    func getStats() -> RenderGraphStats {
        return RenderGraphStats(
            totalPasses: totalPasses,
            activePasses: executionOrder.count,
            culledPasses: culledPasses,
            totalResources: totalResources,
            resourcesReused: resourcesReused,
            isCompiled: isCompiled
        )
    }
}

// MARK: - Supporting Types

struct RenderGraphStats {
    let totalPasses: Int
    let activePasses: Int
    let culledPasses: Int
    let totalResources: Int
    let resourcesReused: Int
    let isCompiled: Bool
}
