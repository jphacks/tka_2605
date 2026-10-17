import AppKit
import Foundation

// Platform adaptation only. All photo storage and game state remain implemented
// by the application's actual EpisodeManager and GameManager sources.
typealias UIImage = NSImage

final class PeerManager {
    static let shared = PeerManager()
    var isConnected = false
    private(set) var sent: [GameMessage] = []

    private init() {}

    func sendPayload(_ payload: GameMessage.Payload, messageID: UUID = UUID()) {
        guard isConnected else { return }
        sent.append(GameMessage(id: messageID, sender: "fake-transport", payload: payload))
    }

    func disconnect() {
        isConnected = false
    }

    func clearSent() {
        sent.removeAll()
    }
}
