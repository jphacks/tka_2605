//
//  ScreenManager.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


enum ScreenState {
    case Title
    case Game
}

@Observable
class ScreenManager {
    private(set) var screenState: ScreenState = .Title
    
    func setScreenState(_ s: ScreenState) {
        self.screenState = s
    }
}
