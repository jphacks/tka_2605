//
//  PeerManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI
import Foundation
import MultipeerConnectivity


struct GameMessage: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case handshake      // 初回接続時の自己紹介/準備完了
        case stateSnapshot  // ゲーム全体の状態同期（ホスト→参加者）
        case playerAction   // プレイヤーの操作（参加者→ホスト or 双方向）
        case chat           // チャットや任意メッセージ
        case heartbeat      // 接続維持・遅延測定など
    }

    // 各メッセージの内容（必要に応じて拡張）
    enum Payload: Codable, Hashable {
        case handshake(name: String)
        case stateSnapshot(state: GameState)
        case playerAction(action: PlayerAction)
        case chat(text: String)
        case heartbeat

        // Codable for enum with associated values
        private enum CodingKeys: String, CodingKey { case type, data }
        private enum Discriminator: String, Codable { case handshake, stateSnapshot, playerAction, chat, heartbeat }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(Discriminator.self, forKey: .type)
            switch type {
            case .handshake:
                let data = try container.decode(HandshakeDTO.self, forKey: .data)
                self = .handshake(name: data.name)
            case .stateSnapshot:
                let state = try container.decode(GameState.self, forKey: .data)
                self = .stateSnapshot(state: state)
            case .playerAction:
                let action = try container.decode(PlayerAction.self, forKey: .data)
                self = .playerAction(action: action)
            case .chat:
                let data = try container.decode(ChatDTO.self, forKey: .data)
                self = .chat(text: data.text)
            case .heartbeat:
                self = .heartbeat
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .handshake(let name):
                try container.encode(Discriminator.handshake, forKey: .type)
                try container.encode(HandshakeDTO(name: name), forKey: .data)
            case .stateSnapshot(let state):
                try container.encode(Discriminator.stateSnapshot, forKey: .type)
                try container.encode(state, forKey: .data)
            case .playerAction(let action):
                try container.encode(Discriminator.playerAction, forKey: .type)
                try container.encode(action, forKey: .data)
            case .chat(let text):
                try container.encode(Discriminator.chat, forKey: .type)
                try container.encode(ChatDTO(text: text), forKey: .data)
            case .heartbeat:
                try container.encode(Discriminator.heartbeat, forKey: .type)
                // no data
            }
        }

        // Small DTOs to keep the payload schema stable
        private struct HandshakeDTO: Codable, Hashable { let name: String }
        private struct ChatDTO: Codable, Hashable { let text: String }
    }

    // メッセージの識別子（重複送信対策や重複排除に利用可能）
    var id: UUID = UUID()

    // 送信者識別（MultipeerのdisplayNameをそのまま文字列で）
    var sender: String

    // メッセージの種別
    var kind: Kind

    // 任意の内容
    var payload: Payload

    // 時刻（遅延測定や順序制御に使用）
    var timestamp: TimeInterval = Date().timeIntervalSince1970
}

// EpisodeManagerが保持するエピソードと進行状態のスナップショット。
struct GameState: Codable, Hashable {
    var episode: Episode
    var data: GameData
}

// プレイヤーの操作内容（ゲームに合わせて拡張）
enum PlayerAction: Codable, Hashable {
    case acquireItem(id: String)

    private enum CodingKeys: String, CodingKey { case type, id }
    private enum Discriminator: String, Codable { case acquireItem }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .acquireItem:
            let id = try container.decode(String.self, forKey: .id)
            self = .acquireItem(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .acquireItem(id):
            try container.encode(Discriminator.acquireItem, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}


@Observable
final class PeerManager: NSObject {
    
    private var player = PlayerManager.shared

    private let serviceType = "haritomato-game"

    private let peerID = MCPeerID(
        displayName: UUID().uuidString
    )

    var connectedPeers: [String] = []
    var discoveredPeers: [MCPeerID] = []
    var messages: [String] = []
    var status = "未接続"
    var displayName: String {
        peerID.displayName
    }

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override private init() {
        super.init()

        session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
    }
    
    static let shared = PeerManager()

    // MARK: - ホスト側

    func startHost() {
        stopDiscovery()
        
        player.setDisplayname(displayName: self.peerID.displayName)

        let service = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )

        service.delegate = self
        advertiser = service
        service.startAdvertisingPeer()

        status = "ホストとして待機中"
    }

    // MARK: - 参加者側

    func startSearching() {
        stopDiscovery()
        
        player.setDisplayname(displayName: self.peerID.displayName)

        let service = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )

        service.delegate = self
        browser = service
        service.startBrowsingForPeers()

        status = "ホストを検索中"
    }

    func join(_ peer: MCPeerID) {
        browser?.invitePeer(
            peer,
            to: session,
            withContext: nil,
            timeout: 30
        )
        status = "\(peer.displayName) に接続中"
    }

    // MARK: - メッセージ送信

    func send(_ message: String) {
        let msg = GameMessage(
            sender: peerID.displayName,
            kind: .chat,
            payload: .chat(text: message)
        )
        send(msg)
    }
    
    func send(_ message: GameMessage) {
        send(message, to: session.connectedPeers)
    }

    private func send(_ message: GameMessage, to peers: [MCPeerID]) {
        guard !peers.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            DispatchQueue.main.async {
                self.status = "送信エラー: \(error.localizedDescription)"
            }
        }
    }

    func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }

    func disconnect() {
        stopDiscovery()
        session.disconnect()
    }
}

// 端末名の取得をプラットフォームごとに分ける
private enum HostName {
    static var current: String {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Device"
        #endif
    }
}


extension PeerManager: MCNearbyServiceAdvertiserDelegate {

    // ホストに参加希望が届いた
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // サンプルでは自動承認。
        // 実際のアプリでは確認画面を挟むのがおすすめ。
        invitationHandler(true, session)
    }
}

extension PeerManager: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
                self.join(peerID)
            }
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}

extension PeerManager: MCSessionDelegate {

    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers.map {
                $0.displayName
            }
            
            switch state {
            case .connected:
                self.status = "\(peerID.displayName) と接続済み"
                self.send(
                    GameMessage(
                        sender: self.peerID.displayName,
                        kind: .handshake,
                        payload: .handshake(name: self.player.selfPlayer.name)
                    ),
                    to: [peerID]
                )
                if self.player.selfPlayer.isHost,
                   let gameState = EpisodeManager.shared.makeGameState() {
                    self.send(
                        GameMessage(
                            sender: self.peerID.displayName,
                            kind: .stateSnapshot,
                            payload: .stateSnapshot(state: gameState)
                        ),
                        to: [peerID]
                    )
                }
            case .connecting:
                self.status = "\(peerID.displayName) に接続中"
            case .notConnected:
                self.status = "\(peerID.displayName) が切断"
            @unknown default:
                self.status = "接続状態不明"
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        do {
            let msg = try JSONDecoder().decode(GameMessage.self, from: data)
            DispatchQueue.main.async {
                switch msg.kind {
                case .chat:
                    if case let .chat(text) = msg.payload {
                        self.messages.append("\(msg.sender): \(text)")
                    }
                case .handshake:
                    // Optionally handle handshake
                    if case let .handshake(name) = msg.payload {
                        let player = Player(name: name, displayName: peerID.displayName, isHost: false)
                        self.player.appendPlayers(player: player)
                    }
                case .stateSnapshot:
                    guard !self.player.selfPlayer.isHost,
                          case let .stateSnapshot(state) = msg.payload else { return }
                    EpisodeManager.shared.applyGameState(state)
                case .playerAction:
                    // Optionally handle actions
                    break
                case .heartbeat:
                    // Optionally handle heartbeat
                    break
                }
            }
        } catch {
            // Fallback: try to interpret as plain text for backward compatibility
            if let message = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.messages.append("\(peerID.displayName): \(message)")
                }
            }
        }
    }

    // 今回はデータ通信のみ使用するため、残りは空実装
    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

