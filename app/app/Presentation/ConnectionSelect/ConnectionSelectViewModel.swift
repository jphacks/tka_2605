//
//  ConnectionSelectViewModel.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


@Observable
class ConnectionSelectViewModel {
    private var player = PlayerManager.shared
    private var screen = ScreenManager.shared
    
    func onClickHostButton() {
        player.setIsHost(isHost: true)
        screen.titleStatePath.append(.EpisodeSelect)
    }
    
    func onClickGuestButton() {
        player.setIsHost(isHost: false)
        screen.titleStatePath.append(.Robbie)
    }
}
