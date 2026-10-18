import SwiftUI

struct ARIntroductionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMoving = false

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 20) {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.light))
                Image(systemName: "iphone")
                    .font(.system(size: 62, weight: .ultraLight))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isMoving ? 15 : -15)))
                    .offset(x: reduceMotion ? 0 : (isMoving ? 12 : -12))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isMoving
                    )
                Image(systemName: "chevron.right")
                    .font(.title2.weight(.light))
            }
            .foregroundStyle(.white.opacity(0.65))
            .accessibilityHidden(true)

            Text("周囲を見渡して証拠をさがせ")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: 270)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
        .padding(16)
        .onAppear { isMoving = true }
    }
}
