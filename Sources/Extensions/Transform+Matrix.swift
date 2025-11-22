import Foundation
import RealityKit
import simd

/// Helper extensions for Transform conversion from matrix
extension Transform {
    /// Initialize Transform from simd_float4x4 matrix
    init(matrix: simd_float4x4) {
        // Extract translation
        let translation = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)

        // Extract scale
        let scaleX = simd_length(SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z))
        let scaleY = simd_length(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        let scaleZ = simd_length(SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        let scale = SIMD3<Float>(scaleX, scaleY, scaleZ)

        // Extract rotation (remove scale from matrix)
        var rotationMatrix = matrix
        rotationMatrix.columns.0 /= scaleX
        rotationMatrix.columns.1 /= scaleY
        rotationMatrix.columns.2 /= scaleZ

        // Convert rotation matrix to quaternion using simd
        let rotation = simd_quaternion(rotationMatrix)

        self.init(scale: scale, rotation: rotation, translation: translation)
    }

    /// Convert Transform to simd_float4x4 matrix
    var matrix: simd_float4x4 {
        // Create rotation matrix from quaternion
        let rotationMatrix3x3 = simd_matrix3x3(rotation)

        // Convert 3x3 to 4x4
        var rotationMatrix = simd_float4x4(
            SIMD4<Float>(rotationMatrix3x3.columns.0.x, rotationMatrix3x3.columns.0.y, rotationMatrix3x3.columns.0.z, 0),
            SIMD4<Float>(rotationMatrix3x3.columns.1.x, rotationMatrix3x3.columns.1.y, rotationMatrix3x3.columns.1.z, 0),
            SIMD4<Float>(rotationMatrix3x3.columns.2.x, rotationMatrix3x3.columns.2.y, rotationMatrix3x3.columns.2.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )

        // Apply scale
        rotationMatrix.columns.0 *= scale.x
        rotationMatrix.columns.1 *= scale.y
        rotationMatrix.columns.2 *= scale.z

        // Add translation
        rotationMatrix.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)

        return rotationMatrix
    }
}
