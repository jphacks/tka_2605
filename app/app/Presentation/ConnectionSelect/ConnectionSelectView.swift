import SwiftUI

struct ConnectionSelectView: View {
    @State var viewModel = ConnectionSelectViewModel()

    private let ink = Color(red: 0.13, green: 0.17, blue: 0.23)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ふたりで、事件の真相へ。")
                        .font(.system(size: 24, weight: .bold))
                    Text("ひとりがホストになり、もうひとりがゲストとして参加してください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 18) {
                    roleCard(
                        title: "ホストとして参加",
                        subtitle: "事件を選んで、相手を待つ",
                        detail: "人的証拠を集める役割です。",
                        symbol: "person.badge.key.fill",
                        accent: Color(red: 0.20, green: 0.43, blue: 0.73),
                        background: Color(red: 0.92, green: 0.96, blue: 1),
                        action: viewModel.onClickHostButton
                    )

                    roleCard(
                        title: "ゲストとして参加",
                        subtitle: "ホストのゲームに参加する",
                        detail: "物的証拠を集める役割です。",
                        symbol: "person.fill",
                        accent: Color(red: 0.48, green: 0.29, blue: 0.72),
                        background: Color(red: 0.96, green: 0.93, blue: 1),
                        action: viewModel.onClickGuestButton
                    )
                }

                Label("このゲームは2人でプレイします", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.985, green: 0.982, blue: 0.975).ignoresSafeArea())
        .navigationTitle("参加方法を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.985, green: 0.982, blue: 0.975), for: .navigationBar)
        .tint(ink)
        .preferredColorScheme(.light)
    }

    private func roleCard(
        title: String,
        subtitle: String,
        detail: String,
        symbol: String,
        accent: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().fill(accent.opacity(0.09))
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(accent.opacity(0.75))
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 9) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(accent)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.65), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}
