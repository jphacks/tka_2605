import SwiftUI

struct TitleView: View {
    @State var viewModel = TitleViewModel()
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack(path: viewModel.path) {
            entryScreen
                .navigationDestination(for: TitleState.self) { screen in
                    switch screen {
                    case .Title:
                        entryScreen
                    case .ConnectionSelect:
                        ConnectionSelectView()
                            .toolbar(.visible, for: .navigationBar)
                    case .EpisodeSelect:
                        EpisodeSelectView()
                    case .Robbie:
                        RobbieView()
                    }
                }
        }
    }

    private var entryScreen: some View {
        VStack {
            // The background and title artwork will be supplied separately.
            Spacer(minLength: 48)

            VStack(alignment: .leading, spacing: 12) {
                Text("プレイヤー名")
                    .font(.subheadline.weight(.medium))
                    .padding(.leading, 8)

                TextField("名前を入力してください", text: $viewModel.name)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .accessibilityLabel("プレイヤー名")

                Button {
                    isNameFocused = false
                    viewModel.onClickStartButton()
                } label: {
                    HStack(spacing: 12) {
                        Text("はじめる")
                        Image(systemName: "arrow.right")
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(viewModel.isActiveStartButton ? 0.35 : 0.85))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 66)
                    .background(.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(.black.opacity(0.08), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isActiveStartButton)
                .padding(.top, 10)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 28)
            .padding(.bottom, isNameFocused ? 24 : 68)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
    }
}
