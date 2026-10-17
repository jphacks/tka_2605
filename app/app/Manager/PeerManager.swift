//
//  PeerManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI
import Foundation
import MultipeerConnectivity


struct Message: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var playerID: UUID
    var message: [String:String] // 未決定
}

@Observable
final class PeerManager: NSObject {

    private let serviceType = "haritomato-game"

    private let peerID = MCPeerID(
        displayName: HostName.current
    )

    var connectedPeers: [String] = []
    var discoveredPeers: [MCPeerID] = []
    var messages: [String] = []
    var status = "未接続"

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
        guard !session.connectedPeers.isEmpty else {
            return
        }

        guard let data = message.data(using: .utf8) else {
            return
        }

        do {
            try session.send(
                data,
                toPeers: session.connectedPeers,
                with: .reliable
            )
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
        guard let message = String(data: data, encoding: .utf8) else {
            return
        }

        DispatchQueue.main.async {
            self.messages.append(
                "\(peerID.displayName): \(message)"
            )
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

