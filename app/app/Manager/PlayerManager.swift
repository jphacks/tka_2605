//
//  PlayerManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


struct Player {
    var id: UUID
    var name: String
    var displayName: String?
    var isHost: Bool = false
    
    init(name: String, displayName: String? = nil, isHost: Bool) {
        self.id = UUID()
        self.name = name
        self.displayName = displayName
        self.isHost = isHost
    }
}

@Observable
class PlayerManager {
    static let shared = PlayerManager()
    
    private(set) var selfPlayer: Player = .init(name: "名無し", isHost: false)
    private(set) var players: [Player] = []
    
    private init() {}
    
    func setDisplayname(displayName: String) {
        self.selfPlayer.displayName = displayName
    }
    
    func setIsHost(isHost: Bool) {
        self.selfPlayer.isHost = isHost
    }
    
    func setName(name: String) {
        self.selfPlayer.name = name
    }
    
    func appendPlayers(player: Player) {
        if let index = players.firstIndex(where: { $0.displayName == player.displayName }) {
            players[index].name = player.name
            players[index].isHost = player.isHost
        } else {
            players.append(player)
        }
    }

    func clearOtherPlayers() {
        players.removeAll()
    }
    
    func serchByDisplayName(name: String) -> Player?{
        return self.players.first {$0.displayName == name}
    }
}
