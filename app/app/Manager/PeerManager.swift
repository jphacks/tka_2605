import SwiftUI
import Foundation
@preconcurrency import MultipeerConnectivity

struct GameMessage: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case handshake, stateSnapshot, playerAction, snapshotAcknowledgement, chat, heartbeat
    }

    enum Payload: Codable, Hashable {
        case handshake(name: String, isHost: Bool)
        case stateSnapshot(state: GameState)
        case playerAction(gameID: UUID, action: PlayerAction)
        case snapshotAcknowledgement(gameID: UUID, revision: Int)
        case chat(text: String)
        case heartbeat
    }

    var id = UUID()
    var sender: String
    var payload: Payload
    var timestamp = Date().timeIntervalSince1970

    var kind: Kind {
        switch payload {
        case .handshake: .handshake
        case .stateSnapshot: .stateSnapshot
        case .playerAction: .playerAction
        case .snapshotAcknowledgement: .snapshotAcknowledgement
        case .chat: .chat
        case .heartbeat: .heartbeat
        }
    }
}

@Observable
final class PeerManager: NSObject {
    static let shared = PeerManager()

    private let serviceType = "haritomato-game"
    private let peerID = MCPeerID(displayName: UUID().uuidString)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var expectedPeer: MCPeerID?
    private var hasVerifiedHandshake = false
    private var isConnecting = false
    @ObservationIgnored private var reconnectTimer: Timer?

    private(set) var connectedPeers: [String] = []
    private(set) var discoveredPeers: [MCPeerID] = []
    private(set) var messages: [String] = []
    private(set) var status = "未接続"

    var displayName: String { peerID.displayName }
    var isConnected: Bool { connectedPeers.count == 1 && hasVerifiedHandshake }

    override private init() {
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func startHost() {
        stopDiscovery()
        PlayerManager.shared.setIsHost(isHost: true)
        PlayerManager.shared.setDisplayname(displayName: displayName)
        let service = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        service.delegate = self
        advertiser = service
        service.startAdvertisingPeer()
        status = "ホストとして待機中"
    }

    func startSearching() {
        stopDiscovery()
        PlayerManager.shared.setIsHost(isHost: false)
        PlayerManager.shared.setDisplayname(displayName: displayName)
        let service = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        service.delegate = self
        browser = service
        service.startBrowsingForPeers()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryConnection() }
        }
        status = "ホストを検索中"
    }

    func join(_ peer: MCPeerID) {
        guard !PlayerManager.shared.selfPlayer.isHost,
              expectedPeer == nil || expectedPeer == peer,
              session.connectedPeers.isEmpty, !isConnecting else { return }
        expectedPeer = peer
        isConnecting = true
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 10)
        status = "ホストに接続中"
    }

    private func retryConnection() {
        if let expectedPeer {
            guard discoveredPeers.contains(expectedPeer) else { return }
            join(expectedPeer)
        } else if let candidate = discoveredPeers.first {
            join(candidate)
        }
    }

    func send(_ text: String) {
        sendPayload(.chat(text: text))
    }

    func send(_ message: GameMessage) {
        guard isConnected else { return }
        sendMessage(message, to: session.connectedPeers)
    }

    func sendPayload(_ payload: GameMessage.Payload, messageID: UUID = UUID()) {
        guard isConnected else { return }
        var message = GameMessage(sender: displayName, payload: payload)
        message.id = messageID
        sendMessage(message, to: session.connectedPeers)
    }

    private func sendMessage(_ message: GameMessage, to peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }
        do {
            try session.send(JSONEncoder().encode(message), toPeers: peers, with: .reliable)
        } catch {
            status = "送信に失敗しました。再接続しています"
            session.disconnect()
        }
    }

    func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    /// 明示的な退出。通信障害時は呼ばず、同じ相手の識別情報を保持する。
    func disconnect() {
        stopDiscovery()
        expectedPeer = nil
        hasVerifiedHandshake = false
        isConnecting = false
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
        PlayerManager.shared.clearOtherPlayers()
        session.disconnect()
        GameManager.shared.connectionDidChange(connected: false)
    }

    private func receive(_ message: GameMessage, from peer: MCPeerID) {
        guard expectedPeer == peer, message.sender == peer.displayName else { return }
        switch message.payload {
        case let .handshake(name, isHost):
            guard isHost != PlayerManager.shared.selfPlayer.isHost else { return }
            hasVerifiedHandshake = true
            PlayerManager.shared.appendPlayers(player: Player(name: name, displayName: peer.displayName, isHost: isHost))
            GameManager.shared.connectionDidChange(connected: true)
        default:
            guard isConnected else { return }
            switch message.payload {
            case let .stateSnapshot(state):
                guard !PlayerManager.shared.selfPlayer.isHost else { return }
                GameManager.shared.receiveSnapshot(state)
            case let .playerAction(gameID, action):
                guard PlayerManager.shared.selfPlayer.isHost else { return }
                GameManager.shared.receiveAction(action, gameID: gameID, messageID: message.id)
            case let .snapshotAcknowledgement(gameID, revision):
                guard PlayerManager.shared.selfPlayer.isHost else { return }
                GameManager.shared.receiveAcknowledgement(gameID: gameID, revision: revision)
            case let .chat(text):
                let name = PlayerManager.shared.serchByDisplayName(name: peer.displayName)?.name ?? "相手"
                messages.append("\(name): \(text)")
            case .heartbeat:
                break
            case .handshake:
                break
            }
        }
    }
}

extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        DispatchQueue.main.async {
            let allowed = PlayerManager.shared.selfPlayer.isHost
                && (self.expectedPeer == nil || self.expectedPeer == peerID)
                && self.session.connectedPeers.allSatisfy { $0 == peerID }
            if allowed { self.expectedPeer = peerID }
            invitationHandler(allowed, allowed ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.status = "ホストの待機を開始できません: \(error.localizedDescription)" }
    }
}

extension PeerManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) { self.discoveredPeers.append(peerID) }
            self.join(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.discoveredPeers.removeAll { $0 == peerID } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.status = "ホストを検索できません: \(error.localizedDescription)" }
    }
}

extension PeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard self.expectedPeer == peerID else { return }
            self.connectedPeers = session.connectedPeers.map(\.displayName)
            switch state {
            case .connected:
                self.isConnecting = false
                self.status = "接続済み"
                self.sendMessage(
                    GameMessage(sender: self.displayName, payload: .handshake(
                        name: PlayerManager.shared.selfPlayer.name,
                        isHost: PlayerManager.shared.selfPlayer.isHost
                    )), to: [peerID]
                )
            case .connecting:
                self.isConnecting = true
                self.status = "接続中"
            case .notConnected:
                self.hasVerifiedHandshake = false
                self.isConnecting = false
                self.status = "接続が切れました。同じ相手を待っています"
                GameManager.shared.connectionDidChange(connected: false)
                // 初回接続に失敗した候補はゲーム開始前なら選び直せる。
                if GameManager.shared.phase == nil && PlayerManager.shared.players.isEmpty {
                    self.expectedPeer = nil
                    // 満員などで拒否された相手へ即座に再招待し続けない。
                    self.discoveredPeers.removeAll { $0 == peerID }
                    self.discoveredPeers.append(peerID)
                }
            @unknown default:
                self.hasVerifiedHandshake = false
                GameManager.shared.connectionDidChange(connected: false)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            guard let message = try? JSONDecoder().decode(GameMessage.self, from: data) else { return }
            self.receive(message, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
