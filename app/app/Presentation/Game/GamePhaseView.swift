import SwiftUI

struct GamePhaseView: View {
    @Bindable var viewModel: GameViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch viewModel.phase {
                case .opening:
                    opening
                case .ending:
                    ending
                case .cleared:
                    cleared
                case .investigation, .none:
                    ProgressView("ゲーム画面へ移動している")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .disabled(!viewModel.isReady && viewModel.phase != .cleared)
        .overlay {
            if !viewModel.isReady && viewModel.phase != .cleared {
                GameConnectionOverlay(message: viewModel.connectionMessage)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .onChange(of: viewModel.synchronization) { _, _ in
            // Observe from the presented view as well as its covered presenter.
            viewModel.synchronize()
        }
        .task {
            viewModel.synchronize()
        }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 36)

            Text(viewModel.episodeName)
                .font(.largeTitle.bold())
            if !viewModel.episodeDescription.isEmpty {
                Text(viewModel.episodeDescription)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.myRoleDescription)
                    .font(.headline)
                Text("周囲をゆっくり映して、証拠の札が配置されるのを待て。札に近づいて撮影すると、証拠を集めることができる。")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

            if viewModel.isHost {
                Button(action: viewModel.beginInvestigation) {
                    Text("2人で調査を始める")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                waiting("ホストが調査を開始するのを待機中。")
            }

            errorMessage
        }
    }

    private var ending: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("推理をまとめる")
                .font(.largeTitle.bold())
                .padding(.top, 20)
            Text("2人共通の人物を決め、それぞれが集めた証拠を1つずつ提示しろ。")
                .foregroundStyle(.secondary)

            if viewModel.hasPreviousIncorrectAttempt {
                Label("提示する証拠が違うようだ。犯人に決定的な証拠を突きつけろ。", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }

            if viewModel.confirmedPersonID == nil {
                personSelection
            } else {
                Label("提示先：\(viewModel.confirmedPersonName)", systemImage: "person.fill")
                    .font(.title3.bold())
                evidenceSelection
            }

            errorMessage
        }
    }

    private var personSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. 提示先の人物")
                .font(.headline)

            if viewModel.isHost {
                ForEach(viewModel.persons) { person in
                    Button {
                        viewModel.selectedPersonID = person.id
                    } label: {
                        selectionLabel(
                            person.name,
                            isSelected: viewModel.selectedPersonID == person.id
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isConfirmingPerson)
                }

                Button(action: viewModel.confirmPerson) {
                    Text(viewModel.isConfirmingPerson ? "人物を確定中…" : "この人物に確定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canConfirmPerson)
            } else {
                waiting("ホストが提示先の人物を決めている。")
            }
        }
    }

    private var evidenceSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. 自分の証拠")
                .font(.headline)

            if viewModel.mySubmittedEvidenceID != nil || viewModel.isSubmittingEvidence {
                if let evidenceID = viewModel.confirmedOrPendingEvidenceID,
                   let evidence = viewModel.myEvidences.first(where: { $0.id == evidenceID }) {
                    Text("提示した証拠：\(evidence.name)")
                        .font(.headline)
                }
                if viewModel.mySubmittedEvidenceID == nil {
                    waiting("証拠を確定中。")
                } else {
                    waiting("相手の証拠を待機中（\(viewModel.submittedCount) / 2人）。")
                }
            } else {
                ForEach(viewModel.myEvidences) { evidence in
                    Button {
                        viewModel.selectedEvidenceID = evidence.id
                    } label: {
                        HStack(spacing: 12) {
                            if let photo = viewModel.photo(for: evidence) {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evidence.name)
                                    .font(.headline)
                                Text(evidence.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: viewModel.selectedEvidenceID == evidence.id
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.selectedEvidenceID == evidence.id
                                                 ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.selectedEvidenceID == evidence.id ? .isSelected : [])
                }

                Button(action: viewModel.submitEvidence) {
                    Text("この証拠を提示する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canSubmitEvidence)
            }
        }
    }

    private var cleared: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 52)
                .accessibilityHidden(true)
            Text("事件解決")
                .font(.largeTitle.bold())
            Text(viewModel.episodeName)
                .font(.title2)
            Text("おめでとう。二人で協力し、見事に事件を解決した。")
                .foregroundStyle(.secondary)

            Button(action: viewModel.returnToTitle) {
                Text("タイトルへ戻る")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let error = viewModel.lastError {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }

    private func waiting(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func selectionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
