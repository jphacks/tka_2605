import SwiftUI

struct GameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = GameViewModel()

    var body: some View {
        GeometryReader { geometry in
            let photographing = viewModel.arMode == .photographing
            let aspectRatio: CGFloat = photographing ? 1 : 9.0 / 16.0
            let progressHeight: CGFloat = viewModel.isInvestigationComplete ? 58 : 0
            let reservedHeight: CGFloat = photographing ? 232 : (viewModel.shouldShowRelocationSuggestion ? 250 : 198) + progressHeight
            let availableHeight = max(1, geometry.size.height - reservedHeight)
            let viewportWidth = min(geometry.size.width - 32, availableHeight * aspectRatio)

            VStack(spacing: 16) {
                heading

                ZStack(alignment: .topTrailing) {
                    // Keep this bridge in the same position for every screen mode.
                    EvidenceARView(runtime: viewModel.arRuntime)

                    if viewModel.isShowingARIntroduction {
                        ARIntroductionView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .task {
                                do {
                                    try await Task.sleep(for: .seconds(5))
                                } catch {
                                    return
                                }
                                withAnimation(.easeOut(duration: 0.4)) {
                                    viewModel.dismissARIntroduction()
                                }
                            }
                    }

                    collectionCounts
                        .padding(12)

                    if photographing {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: max(1, viewportWidth), height: max(1, viewportWidth / aspectRatio))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                investigationControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(!viewModel.isReady || viewModel.isShowingRelocationConfirmation)
            .accessibilityHidden(viewModel.isShowingRelocationConfirmation)
            .overlay {
                if !viewModel.isReady {
                    GameConnectionOverlay(message: viewModel.connectionMessage)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .overlay {
            if viewModel.isShowingRelocationConfirmation {
                EvidenceRelocationConfirmationView(
                    onCancel: viewModel.cancelRelocation,
                    onRelocate: viewModel.confirmRelocation
                )
            }
        }
        .sheet(
            isPresented: $viewModel.isShowingEvidence,
            onDismiss: viewModel.evidenceSheetDidDismiss
        ) {
            EvidenceCollectionView(viewModel: viewModel)
        }
        .fullScreenCover(
            item: $viewModel.phasePresentation,
            onDismiss: viewModel.phaseScreenDidDismiss
        ) { _ in
            GamePhaseView(viewModel: viewModel)
                .interactiveDismissDisabled()
                .onAppear { viewModel.phaseScreenDidAppear() }
        }
        .onChange(of: viewModel.synchronization) { _, _ in
            viewModel.synchronize()
        }
        .onAppear {
            viewModel.gameScreenDidAppear(isSceneActive: scenePhase == .active)
        }
        .task {
            await viewModel.runSearchAssistanceTimer()
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.sceneActivityDidChange(isActive: phase == .active)
        }
        .onDisappear {
            viewModel.stopInteraction()
        }
    }

    private var heading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.episodeName)
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.myRoleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: viewModel.arMode == .photographing ? "camera.fill" : "viewfinder")
                .font(.title3)
                .accessibilityHidden(true)
        }
    }

    private var collectionCounts: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("自分  \(viewModel.myCollectedCount) / \(viewModel.myTotalCount)")
            Text("2人  \(viewModel.totalCollectedCount) / \(viewModel.totalEvidenceCount)")
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var investigationControls: some View {
        VStack(spacing: 10) {
            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if viewModel.arMode == .photographing {
                HStack {
                    Button(action: viewModel.endPhotography) {
                        Label("キャンセル", systemImage: "xmark")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: viewModel.capturePhoto) {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 3)
                            Circle().fill(.white).padding(7)
                            if viewModel.arRuntime.isCapturing {
                                ProgressView().tint(.black)
                            }
                        }
                        .frame(width: 68, height: 68)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.arRuntime.canCapture || viewModel.arRuntime.isCapturing)
                    .opacity(viewModel.arRuntime.canCapture ? 1 : 0.35)
                    .accessibilityLabel("証拠を撮影する")

                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            } else {
                HStack(spacing: 12) {
                    Button(action: viewModel.showEvidence) {
                        Label("証拠", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: viewModel.beginPhotography) {
                        Label("撮影開始", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)

                if viewModel.isInvestigationComplete {
                    if viewModel.isHost {
                        Button(action: viewModel.advanceInvestigation) {
                            Label("ストーリー進展", systemImage: "book.pages")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!viewModel.canAdvanceInvestigation)
                    } else {
                        Text("証拠が揃いました。ホストのストーリー進展を待っています。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if viewModel.shouldShowRelocationSuggestion {
                    Button(action: viewModel.suggestRelocation) {
                        Label("証拠が見つからない？ 再設置する", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var instruction: String {
        if viewModel.arMode == .photographing {
            if let name = viewModel.arRuntime.selectedEvidenceName,
               viewModel.arRuntime.canCapture {
                return "「\(name)」を撮影できます。"
            }
            return "証拠の表面から30cm以内に近づき、画面内の札をタップしてください。"
        }
        return viewModel.arRuntime.statusMessage
    }
}

struct GameConnectionOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("接続を待っています")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 420)
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityElement(children: .combine)
    }
}
