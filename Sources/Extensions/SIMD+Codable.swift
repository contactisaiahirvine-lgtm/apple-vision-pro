import Foundation
import simd

/// Codable conformance for SIMD types used in persistence

// MARK: - SIMD2<Float> Codable

extension SIMD2: Codable where Scalar == Float {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        self.init(x, y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
    }
}

// MARK: - SIMD3<Float> Codable

extension SIMD3: Codable where Scalar == Float {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        self.init(x, y, z)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
    }
}

// MARK: - SIMD4<Float> Codable

extension SIMD4: Codable where Scalar == Float {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        let w = try container.decode(Float.self)
        self.init(x, y, z, w)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
        try container.encode(self.w)
    }
}

// MARK: - simd_quatf Codable

extension simd_quatf: Codable {
    enum CodingKeys: String, CodingKey {
        case vector
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vector = try container.decode(SIMD4<Float>.self, forKey: .vector)
        self.init(vector: vector)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.vector, forKey: .vector)
    }
}
