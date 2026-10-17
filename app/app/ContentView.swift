import SwiftUI
import Playgrounds

struct ContentView: View {
    @State var peer: PeerManager = PeerManager.shared
    @State var episode: EpisodeManager = .init()
    @State var screen = ScreenManager.shared
    
    var body: some View {
        Group {
            switch screen.mainScreenState {
            case .Title:
                TitleView()
            case .Game:
                TitleView()
            }
        }
        .environment(peer)
        .environment(episode)
        
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
