import Foundation
import MultipeerConnectivity
import Combine

@MainActor
class NetworkManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []

    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private let serviceType = "visionpro-game"
    private var cancellables = Set<AnyCancellable>()

    override init() {
        // Create unique peer ID
        let deviceName = "VisionPro_\(Int.random(in: 1000...9999))"
        self.peerID = MCPeerID(displayName: deviceName)

        // Create session
        self.session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        super.init()

        session.delegate = self

        // Listen for player state updates
        NotificationCenter.default.publisher(for: .playerStateUpdated)
            .sink { [weak self] notification in
                guard let player = notification.userInfo?["player"] as? Player else { return }
                self?.broadcastPlayerState(player)
            }
            .store(in: &cancellables)
    }

    // MARK: - Hosting

    func startHosting() {
        stopBrowsing() // Stop browsing if active

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        print("Started hosting as \(peerID.displayName)")
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: - Browsing

    func startBrowsing() {
        stopHosting() // Stop hosting if active

        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        print("Started browsing for peers")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func invitePeer(_ peer: MCPeerID) {
        browser?.invitePeer(
            peer,
            to: session,
            withContext: nil,
            timeout: 30
        )
    }

    // MARK: - Data Transmission

    func broadcastPlayerState(_ player: Player) {
        guard !connectedPeers.isEmpty else { return }
        guard let data = player.serialize() else { return }

        let message = NetworkMessage.playerUpdate(data)
        sendMessage(message)
    }

    func sendMessage(_ message: NetworkMessage) {
        guard !connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }

        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            print("Error sending data: \(error.localizedDescription)")
        }
    }

    private func handleReceivedMessage(_ message: NetworkMessage, from peer: MCPeerID) {
        switch message {
        case .playerUpdate(let playerData):
            if let data = try? JSONDecoder().decode(PlayerNetworkData.self, from: playerData) {
                NotificationCenter.default.post(
                    name: .remotePlayerUpdated,
                    object: nil,
                    userInfo: ["playerData": data]
                )
            }

        case .playerJoined(let playerData):
            if let data = try? JSONDecoder().decode(PlayerNetworkData.self, from: playerData) {
                NotificationCenter.default.post(
                    name: .remotePlayerJoined,
                    object: nil,
                    userInfo: ["playerData": data]
                )
            }

        case .playerLeft(let playerID):
            NotificationCenter.default.post(
                name: .remotePlayerLeft,
                object: nil,
                userInfo: ["playerID": playerID]
            )

        case .gameEvent(let eventData):
            handleGameEvent(eventData, from: peer)

        case .voiceChat(let participantID, let audioData):
            NotificationCenter.default.post(
                name: .voiceChatReceived,
                object: nil,
                userInfo: ["participantID": participantID, "audioData": audioData]
            )
        }
    }

    private func handleGameEvent(_ data: Data, from peer: MCPeerID) {
        // Handle custom game events
        // This can be extended for game-specific logic
        NotificationCenter.default.post(
            name: .gameEventReceived,
            object: nil,
            userInfo: ["data": data, "peer": peer]
        )
    }

    // MARK: - Session Management

    func disconnect() {
        session.disconnect()
        stopHosting()
        stopBrowsing()
        connectedPeers.removeAll()
        availablePeers.removeAll()
        isConnected = false
    }
}

// MARK: - MCSessionDelegate

extension NetworkManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                isConnected = !connectedPeers.isEmpty
                print("Connected to \(peerID.displayName)")

            case .connecting:
                print("Connecting to \(peerID.displayName)")

            case .notConnected:
                connectedPeers.removeAll { $0 == peerID }
                isConnected = !connectedPeers.isEmpty
                print("Disconnected from \(peerID.displayName)")

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else {
                print("Failed to decode message")
                return
            }
            handleReceivedMessage(message, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle stream if needed
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource transfer if needed
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Handle resource transfer completion if needed
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension NetworkManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("Received invitation from \(peerID.displayName)")
            // Auto-accept invitations (you may want to add user confirmation)
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension NetworkManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !availablePeers.contains(peerID) && peerID != self.peerID {
                availablePeers.append(peerID)
                print("Found peer: \(peerID.displayName)")
                // Auto-invite found peers (you may want to add user confirmation)
                invitePeer(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            availablePeers.removeAll { $0 == peerID }
            print("Lost peer: \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }
}

// MARK: - Network Messages

enum NetworkMessage: Codable {
    case playerUpdate(Data)
    case playerJoined(Data)
    case playerLeft(UUID)
    case gameEvent(Data)
    case voiceChat(participantID: UUID, audioData: Data)

    enum CodingKeys: String, CodingKey {
        case type, payload, participantID
    }

    enum MessageType: String, Codable {
        case playerUpdate, playerJoined, playerLeft, gameEvent, voiceChat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .playerUpdate:
            let data = try container.decode(Data.self, forKey: .payload)
            self = .playerUpdate(data)
        case .playerJoined:
            let data = try container.decode(Data.self, forKey: .payload)
            self = .playerJoined(data)
        case .playerLeft:
            let id = try container.decode(UUID.self, forKey: .payload)
            self = .playerLeft(id)
        case .gameEvent:
            let data = try container.decode(Data.self, forKey: .payload)
            self = .gameEvent(data)
        case .voiceChat:
            let participantID = try container.decode(UUID.self, forKey: .participantID)
            let audioData = try container.decode(Data.self, forKey: .payload)
            self = .voiceChat(participantID: participantID, audioData: audioData)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .playerUpdate(let data):
            try container.encode(MessageType.playerUpdate, forKey: .type)
            try container.encode(data, forKey: .payload)
        case .playerJoined(let data):
            try container.encode(MessageType.playerJoined, forKey: .type)
            try container.encode(data, forKey: .payload)
        case .playerLeft(let id):
            try container.encode(MessageType.playerLeft, forKey: .type)
            try container.encode(id, forKey: .payload)
        case .gameEvent(let data):
            try container.encode(MessageType.gameEvent, forKey: .type)
            try container.encode(data, forKey: .payload)
        case .voiceChat(let participantID, let audioData):
            try container.encode(MessageType.voiceChat, forKey: .type)
            try container.encode(participantID, forKey: .participantID)
            try container.encode(audioData, forKey: .payload)
        }
    }
}

// MARK: - Network Notifications

extension Notification.Name {
    static let remotePlayerUpdated = Notification.Name("remotePlayerUpdated")
    static let remotePlayerJoined = Notification.Name("remotePlayerJoined")
    static let remotePlayerLeft = Notification.Name("remotePlayerLeft")
    static let gameEventReceived = Notification.Name("gameEventReceived")
    static let voiceChatReceived = Notification.Name("voiceChatReceived")
}
