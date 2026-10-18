import SwiftUI

struct TitleView: View {
    @State var viewModel = TitleViewModel()
    @FocusState private var isNameFocused: Bool

    private let ivory = Color(red: 0.98, green: 0.95, blue: 0.88)
    private let gold = Color(red: 0.83, green: 0.67, blue: 0.40)
    private let ink = Color(red: 0.06, green: 0.10, blue: 0.14)

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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 28)

                    VStack(spacing: 20) {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 620)
                            .accessibilityLabel("Twin探偵団")

                        Text("ふたりの視点で、真相を解き明かせ。")
                            .font(.system(.subheadline, design: .serif))
                            .tracking(1.2)
                            .foregroundStyle(ink.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 36)

                    Spacer(minLength: 36)

                    entryForm
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, isNameFocused ? 24 : 60)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background { titleBackground }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("プレイヤー名")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ivory.opacity(0.9))
                    .padding(.leading, 8)

                TextField("プレイヤー名", text: $viewModel.name,
                          prompt: Text("名前を入力してください").foregroundStyle(ivory.opacity(0.5)))
                    .font(.body)
                    .foregroundStyle(ivory)
                    .tint(gold)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 56)
                    .background(ink.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isNameFocused ? gold : ivory.opacity(0.3), lineWidth: 1)
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
                    .foregroundStyle(ink.opacity(viewModel.isActiveStartButton ? 0.4 : 1))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 66)
                    .background {
                        Capsule().fill(
                            LinearGradient(colors: [ivory, Color(red: 0.89, green: 0.79, blue: 0.59)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .overlay { Capsule().strokeBorder(ivory.opacity(0.65), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isActiveStartButton)
                .padding(.top, 10)
        }
    }

    private var titleBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Image("blackrose_mansion")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(stops: [
                    .init(color: ivory, location: 0),
                    .init(color: ivory.opacity(0.96), location: 0.28),
                    .init(color: ivory.opacity(0.7), location: 0.45),
                    .init(color: ink.opacity(0.15), location: 0.66),
                    .init(color: ink.opacity(0.9), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
