import SwiftUI

struct EpisodeSelectView: View {
    @State var viewModel = EpisodeSelectViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(Array(viewModel.getEpisodes().enumerated()), id: \.element.id) { index, episode in
                    Button {
                        viewModel.onClickEpisodeButton(episodeID: episode.id)
                    } label: {
                        episodeCard(episode, number: index + 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(!episode.isActive)
                    .accessibilityLabel("第\(index + 1)話、\(episode.name)\(episode.isActive ? "" : "、未公開")")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.985, green: 0.982, blue: 0.975).ignoresSafeArea())
        .navigationTitle("事件を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.985, green: 0.982, blue: 0.975), for: .navigationBar)
        .tint(Color(red: 0.15, green: 0.18, blue: 0.22))
        .preferredColorScheme(.light)
        .fullScreenCover(
            item: Binding(
                get: { viewModel.selectedEpisode },
                set: { if $0 == nil { viewModel.cancelEpisodeSelection() } }
            ),
            onDismiss: viewModel.confirmationDidDismiss
        ) { episode in
            EpisodePlayConfirmationView(
                episode: episode,
                onCancel: viewModel.cancelEpisodeSelection,
                onPlay: viewModel.confirmEpisodeSelection
            )
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
        .onAppear { viewModel.connectClose() }
    }

    private func episodeCard(_ episode: Episode, number: Int) -> some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black)
                .frame(width: 104, height: 144)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                Text(String(format: "#%02d", number))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(episode.name)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: episode.isActive ? "chevron.right" : "lock")
                .font(.system(size: episode.isActive ? 20 : 25, weight: .regular))
                .foregroundStyle(episode.isActive ? Color.secondary : Color.gray)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
        .foregroundStyle(episode.isActive ? Color(red: 0.16, green: 0.18, blue: 0.21) : Color(red: 0.43, green: 0.43, blue: 0.44))
        .padding(12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            episode.isActive
                ? Color(red: 0.91, green: 0.94, blue: 0.97)
                : Color(red: 0.88, green: 0.88, blue: 0.88),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}
