import Foundation
import SwiftUI
import RealityKit

/// Handles input processing for the game
class InputController {
    /// Convert screen drag gesture to 3D movement direction
    static func dragToMovement(_ drag: CGSize, sensitivity: Float = 0.01) -> SIMD3<Float> {
        let x = Float(drag.width) * sensitivity
        let z = -Float(drag.height) * sensitivity
        return SIMD3<Float>(x, 0, z)
    }

    /// Normalize movement direction
    static func normalizeMovement(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(direction)
        guard length > 0 else { return .zero }
        return direction / length
    }

    /// Apply dead zone to movement
    static func applyDeadZone(_ value: Float, deadZone: Float = 0.1) -> Float {
        if abs(value) < deadZone {
            return 0
        }
        return value
    }
}
