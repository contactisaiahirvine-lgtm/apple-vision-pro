import Foundation
import Combine

extension GameManager {
    /// Setup network event listeners
    func setupNetworkListeners() {
        // Listen for remote player updates
        NotificationCenter.default.publisher(for: .remotePlayerUpdated)
            .sink { [weak self] notification in
                guard let playerData = notification.userInfo?["playerData"] as? PlayerNetworkData else { return }
                self?.updateRemotePlayer(data: playerData)
            }
            .store(in: &cancellables)

        // Listen for remote player joined
        NotificationCenter.default.publisher(for: .remotePlayerJoined)
            .sink { [weak self] notification in
                guard let playerData = notification.userInfo?["playerData"] as? PlayerNetworkData else { return }
                let newPlayer = Player(id: playerData.id, name: playerData.name, isLocal: false)
                newPlayer.update(from: playerData)
                Task {
                    await self?.addRemotePlayer(newPlayer)
                }
            }
            .store(in: &cancellables)

        // Listen for remote player left
        NotificationCenter.default.publisher(for: .remotePlayerLeft)
            .sink { [weak self] notification in
                guard let playerID = notification.userInfo?["playerID"] as? UUID else { return }
                self?.removeRemotePlayer(id: playerID)
            }
            .store(in: &cancellables)

        // Listen for game events
        NotificationCenter.default.publisher(for: .gameEventReceived)
            .sink { [weak self] notification in
                guard let data = notification.userInfo?["data"] as? Data else { return }
                self?.handleGameEvent(data)
            }
            .store(in: &cancellables)
    }

    private func handleGameEvent(_ data: Data) {
        // Handle custom game events
        // Example: items spawned, game state changes, etc.
        print("Received game event with \(data.count) bytes")
    }

    private var cancellables: Set<AnyCancellable> {
        get {
            // CRITICAL FIX: Ensure the Set is persisted if it doesn't exist
            if let existing = objc_getAssociatedObject(self, &AssociatedKeys.cancellables) as? Set<AnyCancellable> {
                return existing
            }
            // Create and persist a new Set
            let newSet = Set<AnyCancellable>()
            objc_setAssociatedObject(self, &AssociatedKeys.cancellables, newSet, .OBJC_ASSOCIATION_RETAIN)
            return newSet
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.cancellables, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

private struct AssociatedKeys {
    static var cancellables = "cancellables"
}
