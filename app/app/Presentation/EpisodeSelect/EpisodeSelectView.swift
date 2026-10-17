//
//  EpisodeSelectView.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI

struct EpisodeSelectView: View {
    @State var viewModel = EpisodeSelectViewModel()

    var body: some View {
        List {
            ForEach(viewModel.getEpisodes(), id: \.id) { episode in
                VStack {
                    Button(
                        action: {
                            viewModel.onClickEpisodeButton(
                                episodeID: episode.id
                            )
                        }
                    ) {
                        Text(episode.name).font(.headline)
                        Text(episode.description)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(96)
                }
            }
        }
    }
}
