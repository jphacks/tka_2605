import SwiftUI

struct EvidenceCollectionView: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.photographedEvidences.isEmpty {
                    ContentUnavailableView(
                        "証拠はまだありません",
                        systemImage: "camera",
                        description: Text("ARの札を撮影すると、ここで写真と詳細を確認できます。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.photographedEvidences) { evidence in
                                evidenceCard(evidence)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("撮影した証拠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .disabled(!viewModel.isReady)
            .overlay {
                if !viewModel.isReady {
                    GameConnectionOverlay(message: viewModel.connectionMessage)
                }
            }
        }
        .interactiveDismissDisabled(!viewModel.isReady)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.synchronization) { _, _ in
            viewModel.synchronize()
        }
    }

    private func evidenceCard(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if let image = viewModel.photo(for: evidence) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("\(evidence.name)の撮影写真")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(evidence.name)
                        .font(.headline)
                    Text(evidence.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { } label: {
                Label("村人に話を聞く（準備中）", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
    }
}
