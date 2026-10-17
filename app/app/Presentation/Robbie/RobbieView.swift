//
//  RobbieView.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI

struct RobbieView: View {
    @State var viewModel = RobbieViewModel()

    var body: some View {
        List {
            if let title = viewModel.getEpisodeTitle() {
                Text(title).font(.title)
            }
            if let description = viewModel.getEpisodeDescription() {
                Text(description)
            }

            if let count = viewModel.getPlayerCount() {
                HStack {
                    Text("接続人数....")
                    Text(count + " / 2")
                }
            } else {
                Text("???")
            }
            
            

            ForEach(viewModel.getPlayersName(), id: \.self) { name in
                Text(name)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(96)
            }
            if let isActive = viewModel.isActiveStartButton {
                Button("推理開始", action: viewModel.onClickStartButton)
                    .disabled(!isActive)
                    .buttonStyle(.plain)
            }
        }
        .onAppear {
            viewModel.startConnection()
        }
    }
}
