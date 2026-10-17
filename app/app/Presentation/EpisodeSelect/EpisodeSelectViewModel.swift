//
//  EpisodeSelectViewModel.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


import SwiftUI


@Observable
class EpisodeSelectViewModel {
    private var episode = EpisodeManager.shared
    private var screen = ScreenManager.shared
    private var peer = PeerManager.shared
    
    var episodeID: Int? = nil
    
    func getEpisodes() -> [Episode] {
        return episode.getAllEpisode()
    }
    
    func onClickEpisodeButton(episodeID: Int) {
        self.episodeID = episodeID
        
        guard let episodeID = self.episodeID else { return }
        
        self.episode.initFromEpisodeID(id: episodeID)
        screen.titleStatePath.append(.Robbie)
    }
    
    func connectClose() {
        self.peer.disconnect()
    }
}
