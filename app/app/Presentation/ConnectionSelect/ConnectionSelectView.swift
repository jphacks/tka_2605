//
//  ConnectionSelectView.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


struct ConnectionSelectView: View {
    @State var viewModel = ConnectionSelectViewModel()
    
    var body: some View {
        VStack {
            Group {
                Button("ホストとして参加", action: viewModel.onClickHostButton)
                Button("ゲストとして参加", action: viewModel.onClickGuestButton)
            }
            .backgroundStyle(.blue)
            .padding(96)
        }
    }
}
