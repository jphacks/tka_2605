//
//  PeerSampleView.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import Playgrounds
import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @State private var peer = PeerManager()
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(peer.status)
                    .font(.headline)

                HStack {
                    Button("ホストになる") {
                        peer.startHost()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("参加する") {
                        peer.startSearching()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                Text("接続中: \(peer.connectedPeers.count) 台")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("見つかった端末")
                    .frame(maxWidth: .infinity, alignment: .leading)

                List(peer.discoveredPeers, id: \.self) { device in
                    HStack {
                        Text(device.displayName)

                        Spacer()

                        Button("接続") {
                            peer.join(device)
                        }
                    }
                }
                .frame(minHeight: 100)

                HStack {
                    TextField("メッセージ", text: $input)
                        .textFieldStyle(.roundedBorder)

                    Button("送信") {
                        let message = input
                        guard !message.isEmpty else { return }

                        peer.send(message)
                        input = ""
                    }
                    .disabled(peer.connectedPeers.isEmpty)
                }

                Text("受信メッセージ")
                    .frame(maxWidth: .infinity, alignment: .leading)

                List(peer.messages.indices, id: \.self) { index in
                    Text(peer.messages[index])
                }

                Button("切断") {
                    peer.disconnect()
                }
                .foregroundStyle(.red)
            }
            .padding()
            .navigationTitle("ローカル通信")
        }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
