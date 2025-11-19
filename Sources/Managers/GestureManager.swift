import Foundation
import UIKit
import RealityKit
import Combine

/// Advanced gesture manager for Vision Pro interactions
@MainActor
class GestureManager: ObservableObject {

    // MARK: - Published Properties

    @Published var activePinches: Set<UUID> = []
    @Published var currentGestureType: GestureType = .none

    // MARK: - Private Properties

    private weak var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    // Gesture recognizers
    private var pinchGesture: UIGestureRecognizer?
    private var pinchAndHoldGesture: UILongPressGestureRecognizer?
    private var dragGesture: UIPanGestureRecognizer?
    private var rotationGesture: UIRotationGestureRecognizer?
    private var scaleGesture: UIPinchGestureRecognizer?

    // Gesture state
    private var pinchStartTime: Date?
    private var pinchStartPosition: CGPoint?
    private var selectedEntity: Entity?

    // MARK: - Callbacks

    var onPinch: ((CGPoint) -> Void)?
    var onPinchAndHold: ((CGPoint, TimeInterval) -> Void)?
    var onDrag: ((CGPoint, CGPoint) -> Void)?  // start, current
    var onRotate: ((Float) -> Void)?  // angle in radians
    var onScale: ((Float) -> Void)?  // scale factor

    // Entity-specific callbacks
    var onEntityPinched: ((Entity) -> Void)?
    var onEntityDragged: ((Entity, CGPoint) -> Void)?
    var onEntityReleased: ((Entity) -> Void)?

    // MARK: - Initialization

    init() {
        print("GestureManager initialized")
    }

    func setup(arView: ARView) {
        self.arView = arView
        setupGestureRecognizers()
    }

    // MARK: - Gesture Setup

    private func setupGestureRecognizers() {
        guard let arView = arView else { return }

        // Standard tap (already handled by PlacementManager, but can extend)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        arView.addGestureRecognizer(tap)

        // Double tap
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        arView.addGestureRecognizer(doubleTap)

        // Prevent single tap from firing when double tap succeeds
        tap.require(toFail: doubleTap)

        // Long press (pinch and hold simulation)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        pinchAndHoldGesture = longPress
        arView.addGestureRecognizer(longPress)

        // Pan/Drag
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        dragGesture = pan
        arView.addGestureRecognizer(pan)

        // Rotation
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture = rotation
        arView.addGestureRecognizer(rotation)

        // Pinch/Scale
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        scaleGesture = pinch
        arView.addGestureRecognizer(pinch)

        // Allow simultaneous gestures
        pan.delegate = self
        rotation.delegate = self
        pinch.delegate = self

        print("Gestures configured")
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let location = gesture.location(in: gesture.view)

        // Notify
        NotificationCenter.default.post(
            name: .gestureTap,
            object: nil,
            userInfo: ["location": location]
        )

        // Check for entity hit
        if let entity = hitTestEntity(at: location) {
            onPinch?(location)
            onEntityPinched?(entity)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let location = gesture.location(in: gesture.view)

        NotificationCenter.default.post(
            name: .gestureDoubleTap,
            object: nil,
            userInfo: ["location": location]
        )
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: gesture.view)

        switch gesture.state {
        case .began:
            currentGestureType = .pinchAndHold
            pinchStartTime = Date()
            pinchStartPosition = location

            // Select entity if hit
            selectedEntity = hitTestEntity(at: location)

            NotificationCenter.default.post(
                name: .gestureLongPressBegan,
                object: nil,
                userInfo: ["location": location, "entity": selectedEntity as Any]
            )

        case .changed:
            if let startTime = pinchStartTime {
                let duration = Date().timeIntervalSince(startTime)
                onPinchAndHold?(location, duration)
            }

        case .ended, .cancelled:
            currentGestureType = .none

            if let entity = selectedEntity {
                onEntityReleased?(entity)
            }

            NotificationCenter.default.post(
                name: .gestureLongPressEnded,
                object: nil,
                userInfo: ["location": location]
            )

            pinchStartTime = nil
            pinchStartPosition = nil
            selectedEntity = nil

        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: gesture.view)

        switch gesture.state {
        case .began:
            currentGestureType = .drag
            pinchStartPosition = location

            // Select entity if hit
            selectedEntity = hitTestEntity(at: location)

            NotificationCenter.default.post(
                name: .gestureDragBegan,
                object: nil,
                userInfo: ["location": location, "entity": selectedEntity as Any]
            )

        case .changed:
            if let startPos = pinchStartPosition {
                onDrag?(startPos, location)

                if let entity = selectedEntity {
                    onEntityDragged?(entity, location)
                }
            }

        case .ended, .cancelled:
            currentGestureType = .none

            if let entity = selectedEntity {
                onEntityReleased?(entity)
            }

            NotificationCenter.default.post(
                name: .gestureDragEnded,
                object: nil,
                userInfo: ["location": location]
            )

            pinchStartPosition = nil
            selectedEntity = nil

        default:
            break
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            currentGestureType = .rotation

        case .changed:
            let rotation = Float(gesture.rotation)
            onRotate?(rotation)

            NotificationCenter.default.post(
                name: .gestureRotation,
                object: nil,
                userInfo: ["rotation": rotation]
            )

        case .ended, .cancelled:
            currentGestureType = .none
            gesture.rotation = 0  // Reset

        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            currentGestureType = .scale

        case .changed:
            let scale = Float(gesture.scale)
            onScale?(scale)

            NotificationCenter.default.post(
                name: .gestureScale,
                object: nil,
                userInfo: ["scale": scale]
            )

        case .ended, .cancelled:
            currentGestureType = .none
            gesture.scale = 1.0  // Reset

        default:
            break
        }
    }

    // MARK: - Hit Testing

    private func hitTestEntity(at point: CGPoint) -> Entity? {
        guard let arView = arView else { return nil }

        let hitEntities = arView.entities(at: point)
        return hitEntities.first
    }

    // MARK: - Custom Gestures

    /// Enable pinch gesture (simulated with tap)
    func registerPinchGesture(onPinch: @escaping (CGPoint) -> Void) {
        self.onPinch = onPinch
    }

    /// Enable drag gesture
    func registerDragGesture(onDrag: @escaping (CGPoint, CGPoint) -> Void) {
        self.onDrag = onDrag
    }

    /// Enable rotation gesture
    func registerRotationGesture(onRotate: @escaping (Float) -> Void) {
        self.onRotate = onRotate
    }

    /// Enable scale gesture
    func registerScaleGesture(onScale: @escaping (Float) -> Void) {
        self.onScale = onScale
    }

    // MARK: - Utilities

    func isGestureActive() -> Bool {
        return currentGestureType != .none
    }
}

// MARK: - UIGestureRecognizerDelegate

extension GestureManager: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pan, rotation, and pinch to work together
        return true
    }
}

// MARK: - Gesture Types

enum GestureType: Equatable {
    case none
    case tap
    case doubleTap
    case pinch
    case pinchAndHold
    case drag
    case rotation
    case scale
}

// MARK: - Notifications

extension Notification.Name {
    static let gestureTap = Notification.Name("gestureTap")
    static let gestureDoubleTap = Notification.Name("gestureDoubleTap")
    static let gestureLongPressBegan = Notification.Name("gestureLongPressBegan")
    static let gestureLongPressEnded = Notification.Name("gestureLongPressEnded")
    static let gestureDragBegan = Notification.Name("gestureDragBegan")
    static let gestureDragEnded = Notification.Name("gestureDragEnded")
    static let gestureRotation = Notification.Name("gestureRotation")
    static let gestureScale = Notification.Name("gestureScale")
}
