//
//  ScreenManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


enum MainScreenState {
    case Title
    case Game
}

enum TitleState: Hashable {
    case Title
    case ConnectionSelect
    case EpisodeSelect
    case Robbie
}


@Observable
class ScreenManager {
    static let shared = ScreenManager()
    
    private init() {}
    
    private(set) var mainScreenState: MainScreenState = .Title
    var titleStatePath: [TitleState] = [.Title]
    
    func setScreenState(_ s: MainScreenState) {
        self.mainScreenState = s
    }
}
