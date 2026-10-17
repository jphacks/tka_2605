//
//  TitleView.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


struct TitleView: View {
    @State var viewModel = TitleViewModel()
    
    let title: String = "タイトル"
    let buttonLabel: String = "ボタン"
    
    var body: some View {
        NavigationStack(path: viewModel.path) {
            VStack {
                Text(title)
                Spacer()
                
                TextField("名前を入力", text: $viewModel.name)
                
                Button(buttonLabel, action: viewModel.onClickStartButton)
                    .backgroundStyle(.blue)
                    .padding()
                    .disabled(viewModel.isActiveStartButton)
            }
            .padding()
            .navigationDestination(for: TitleState.self) { screen in
                switch screen {
                case .Title:
                    TitleView()
                case .ConnectionSelect:
                    ConnectionSelectView()
                case .EpisodeSelect:
                    EpisodeSelectView()
                case .Robbie:
                    EmptyView()
                }
            }
        }
    }
}
