import SwiftUI

struct EpisodePlayConfirmationView: View {
    let episode: Episode
    let onCancel: () -> Void
    let onPlay: () -> Void

    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color(red: 0.20, green: 0.43, blue: 0.73))
                        .frame(width: 64, height: 64)
                        .background(Color(red: 0.92, green: 0.96, blue: 1), in: Circle())
                        .accessibilityHidden(true)

                    Text("事件をプレイしますか？")
                        .font(.system(size: 21, weight: .bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isHeadingFocused)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(episode.name)
                                .font(.headline)
                            Text(episode.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: min(220, geometry.size.height * 0.28))
                    .scrollBounceBehavior(.basedOnSize)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            cancelButton
                            playButton
                        }
                        VStack(spacing: 12) {
                            playButton
                            cancelButton
                        }
                    }
                }
                .foregroundStyle(Color(red: 0.13, green: 0.17, blue: 0.23))
                .padding(24)
                .frame(maxWidth: 420)
                .background(.white, in: RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
                .padding(24)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onCancel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.light)
        .onAppear { isHeadingFocused = true }
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text("キャンセル")
                .font(.body.weight(.semibold))
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.42))
                .background(Color(red: 0.94, green: 0.95, blue: 0.96), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Text("プレイする")
                .font(.body.weight(.semibold))
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(Color(red: 0.20, green: 0.49, blue: 0.98), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}
