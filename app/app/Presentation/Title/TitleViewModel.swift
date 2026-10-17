//
//  TitleViewModel.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


@Observable
class TitleViewModel {
    private var screen = ScreenManager.shared
    private var player = PlayerManager.shared
    
    var name: String = ""
    
    var path: Binding<[TitleState]> {
        Binding(
            get: { self.screen.titleStatePath },
            set: { self.screen.titleStatePath = $0
        })
    }
    
    var isActiveStartButton: Bool {
        name.isEmpty
    }
    
    init() {}
    
    func onClickStartButton() {
        player.setName(name: name)
        screen.titleStatePath.append(.ConnectionSelect)
    }
}
