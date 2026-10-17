//
//  RobbieViewModel.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


import SwiftUI


@Observable
class RobbieViewModel {
    private var episode = EpisodeManager.shared
    private var player = PlayerManager.shared
    private var screen = ScreenManager.shared
    private var peer = PeerManager.shared
    
    var isActiveStartButton: Bool? {
        if player.selfPlayer.isHost {
            return GameManager.shared.isReady
        } else {
            return nil
        }
    }
    
    func getEpisodeTitle() -> String? {
        episode.episode?.name
    }
    
    func getEpisodeDescription() -> String? {
        episode.episode?.description
    }
    
    func getPlayerCount() -> String? {
        String(peer.connectedPeers.count + 1)
    }
    
    func onClickStartButton() {
        GameManager.shared.startGame()
    }
    
    func getPlayersName() -> [String] {
        
        var playersName: [String] = peer.connectedPeers.compactMap { peerID in
            player.serchByDisplayName(name: peerID)?.name
        }
    
        playersName.append(player.selfPlayer.name)
        return playersName
    }
    
    func startConnection() {
        if player.selfPlayer.isHost {
            peer.startHost()
        } else {
            peer.startSearching()
        }
    }
}
