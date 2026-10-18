import SwiftUI

struct EvidenceRelocationConfirmationView: View {
    let onCancel: () -> Void
    let onRelocate: () -> Void

    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("証拠を再設置しますか？")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)

                Text("まだ取得していない証拠を、周囲の条件に合う場所に置き直します。取得済みの証拠と写真はそのまま残ります。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        cancelButton
                        relocateButton
                    }
                    VStack(spacing: 12) {
                        relocateButton
                        cancelButton
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onCancel)
        }
        .onAppear { isHeadingFocused = true }
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text("キャンセル")
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var relocateButton: some View {
        Button(action: onRelocate) {
            Text("再設置する")
                .fixedSize()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }
}
