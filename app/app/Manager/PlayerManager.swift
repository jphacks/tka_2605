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
    private(set) var selfPlayer: Player?
    private(set) var players: [Player]
    
    init(selfPlayer: Player? = nil) {
        self.selfPlayer = selfPlayer
        self.players = []
    }
    
    func initSelfPlayer(player: Player) {
        self.selfPlayer = player
    }
    
    func appendPlayers(player: Player) {
        self.players.append(player)
    }
}
