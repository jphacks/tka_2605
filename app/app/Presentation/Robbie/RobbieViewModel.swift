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
            return peer.connectedPeers.count >= 1 ? true : false
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
        screen.setScreenState(.Game)
    }
    
    func getPlayersName() -> [String] {
        return peer.connectedPeers
    }
    
    func startConnection() {
        if player.selfPlayer.isHost {
            peer.startHost()
        } else {
            peer.startSearching()
        }
        
        sync()
    }
    
    private func sync() {
        guard player.selfPlayer.isHost else { return }
    }
}

/*
 
 ホストー＞ゲストにエピソード情報を送信
 
 */
