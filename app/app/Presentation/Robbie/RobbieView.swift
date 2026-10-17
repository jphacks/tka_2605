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
                Text(count + "/ 2")
            } else {
                Text("???")
            }

            ForEach(viewModel.getPlayersName(), id: \.self) { name in
                Text(name)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(96)
            }
        }
    }
}
