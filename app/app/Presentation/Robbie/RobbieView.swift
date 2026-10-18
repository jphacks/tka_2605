import SwiftUI

struct RobbieView: View {
    @State var viewModel = RobbieViewModel()

    private let ink = Color(red: 0.13, green: 0.17, blue: 0.23)
    private var names: [String] { viewModel.getPlayersName() }
    private var selfIsHost: Bool { viewModel.isActiveStartButton != nil }
    private var hostName: String? { selfIsHost ? names.last : names.dropLast().first }
    private var guestName: String? { selfIsHost ? names.dropLast().first : names.last }
    private var membersReady: Bool {
        names.count == 2 && viewModel.getEpisodeTitle() != nil && viewModel.isActiveStartButton != false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                episodeSummary

                VStack(spacing: 14) {
                    HStack {
                        Text("参加メンバー")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(viewModel.getPlayerCount() ?? "1") / 2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.bottom, 2)

                    memberCard(name: hostName, isHost: true)
                    memberCard(name: guestName, isHost: false)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startControl
                .frame(maxWidth: 596)
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background(.white)
        }
        .navigationTitle(viewModel.getEpisodeTitle() ?? "参加を待っています")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ink)
        .preferredColorScheme(.light)
        .onAppear { viewModel.startConnection() }
    }

    private var episodeSummary: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black)
                .frame(width: 110, height: 128)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.getEpisodeTitle() ?? "エピソードを受信中")
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                Text(viewModel.getEpisodeDescription() ?? "ホストが選んだ事件の情報を待っている。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.96, green: 0.96, blue: 0.965), in: RoundedRectangle(cornerRadius: 22))
    }

    private func memberCard(name: String?, isHost: Bool) -> some View {
        let accent = isHost
            ? Color(red: 0.20, green: 0.43, blue: 0.73)
            : Color(red: 0.48, green: 0.29, blue: 0.72)
        let background = isHost
            ? Color(red: 0.92, green: 0.96, blue: 1)
            : Color(red: 0.96, green: 0.93, blue: 1)

        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.09))
                Image(systemName: "person.fill")
                    .font(.system(size: 39, weight: .regular))
                    .foregroundStyle(accent.opacity(name == nil ? 0.25 : 0.55))
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(name ?? (isHost ? "ホストを待っています" : "参加者を待っています"))
                        .font(.headline)
                        .lineLimit(2)
                    if isHost, name != nil {
                        Text("ホスト")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.10), in: Capsule())
                    }
                }
                .foregroundStyle(accent)

                if name != nil, membersReady {
                    Label("準備OK", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.64, blue: 0.30))
                } else {
                    Text(name == nil ? "接続待ち" : "接続待機中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "iphone")
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(accent.opacity(0.75))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var startControl: some View {
        if let isActive = viewModel.isActiveStartButton {
            Button(action: viewModel.onClickStartButton) {
                Text("ゲームスタート")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 62)
                    .background(
                        Color(red: 0.20, green: 0.49, blue: 0.98).opacity(isActive ? 1 : 0.45),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isActive)
        } else {
            Text("ホストがゲームを開始するのを待っています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 62)
        }
    }
}
