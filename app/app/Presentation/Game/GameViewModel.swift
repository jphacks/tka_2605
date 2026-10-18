import SwiftUI

enum ARScreenMode {
    case exploring
    case photographing
}

struct GamePhasePresentation: Identifiable {
    let id = "game-phase"
}

struct GameViewSynchronization: Equatable {
    let gameID: UUID?
    let revision: Int
    let phase: GamePhase?
    let isReady: Bool
    let hasCameraFeed: Bool
    let error: String?
}

@Observable
@MainActor
final class GameViewModel {
    private let game: GameManager
    private let episode: EpisodeManager
    let arRuntime: EvidenceARRuntime

    private(set) var arMode: ARScreenMode = .exploring
    var isShowingEvidence = false
    var phasePresentation: GamePhasePresentation?
    var selectedPersonID: Int?
    var selectedEvidenceID: Int?
    private(set) var isConfirmingPerson = false
    private(set) var isShowingARIntroduction = false

    private var currentGameID: UUID?
    private var hasShownARIntroduction = false
    private var isPhaseScreenVisible = false
    private var currentAttempt: Int?
    private var previousPhase: GamePhase?
    private var evidenceSheetIsActive = false
    private var activeCaptureID: UUID?

    init(
        game: GameManager? = nil,
        episode: EpisodeManager? = nil,
        arRuntime: EvidenceARRuntime? = nil
    ) {
        self.game = game ?? .shared
        self.episode = episode ?? .shared
        self.arRuntime = arRuntime ?? EvidenceARRuntime()
    }

    var synchronization: GameViewSynchronization {
        GameViewSynchronization(
            gameID: game.state?.data.id,
            revision: game.state?.revision ?? -1,
            phase: game.phase,
            isReady: game.isReady,
            hasCameraFeed: arRuntime.hasCameraFeed,
            error: game.lastError
        )
    }

    var phase: GamePhase? { game.phase }
    var isReady: Bool { game.isReady }
    var isHost: Bool { game.isHost }
    var episodeName: String { game.state?.episode.name ?? "調査" }
    var episodeDescription: String { game.state?.episode.description ?? "" }
    var connectionMessage: String {
        game.connectionMessage ?? "相手との接続と状態の同期を待っています。"
    }
    var lastError: String? { game.lastError }
    var myCollectedCount: Int { game.myCollectedCount }
    var myTotalCount: Int { game.myTotalCount }
    var totalCollectedCount: Int { game.totalCollectedCount }
    var totalEvidenceCount: Int { game.totalEvidenceCount }
    var myEvidences: [Evidence] { game.myEvidences }
    var myRoleDescription: String { isHost ? "人的証拠を集める" : "物的証拠を集める" }

    var photographedEvidences: [Evidence] {
        myEvidences.filter { photo(for: $0) != nil }
    }

    var persons: [Person] {
        game.state?.data.persons.filter { $0.id != 0 } ?? []
    }

    var confirmedPersonID: Int? { game.state?.ending.personID }

    var confirmedPersonName: String {
        persons.first { $0.id == confirmedPersonID }?.name ?? "選択した人物"
    }

    var mySubmittedEvidenceID: Int? {
        isHost ? game.state?.ending.hostEvidenceID : game.state?.ending.guestEvidenceID
    }

    var isSubmittingEvidence: Bool { game.myPendingEvidenceID != nil }

    var confirmedOrPendingEvidenceID: Int? {
        mySubmittedEvidenceID ?? game.myPendingEvidenceID
    }

    var submittedCount: Int {
        guard let ending = game.state?.ending else { return 0 }
        return (ending.hostEvidenceID == nil ? 0 : 1)
            + (ending.guestEvidenceID == nil ? 0 : 1)
    }

    var hasPreviousIncorrectAttempt: Bool {
        (game.state?.ending.attempt ?? 0) > 0
    }

    var canConfirmPerson: Bool {
        isReady && isHost && phase == .ending && confirmedPersonID == nil
            && selectedPersonID != nil && !isConfirmingPerson
    }

    var canSubmitEvidence: Bool {
        isReady && phase == .ending && confirmedPersonID != nil
            && selectedEvidenceID != nil && mySubmittedEvidenceID == nil
            && !isSubmittingEvidence
    }

    func photo(for evidence: Evidence) -> UIImage? {
        episode.photo(for: EvidenceKey(kind: game.myKind, id: evidence.id))
    }

    /// Reconcile shared progress without rebuilding the local AR session.
    func synchronize() {
        if currentGameID != game.state?.data.id {
            hasShownARIntroduction = false
            dismissARIntroduction()
            endPhotography()
            selectedPersonID = nil
            selectedEvidenceID = nil
            isConfirmingPerson = false
            currentGameID = game.state?.data.id
            currentAttempt = nil
        }

        if let state = game.state {
            arRuntime.configure(
                gameID: state.data.id,
                evidences: game.myEvidences,
                kind: game.myKind
            )
            if currentAttempt != state.ending.attempt {
                selectedPersonID = nil
                selectedEvidenceID = nil
                isConfirmingPerson = false
                currentAttempt = state.ending.attempt
            }
        }

        if previousPhase != phase {
            isConfirmingPerson = false
            previousPhase = phase
        }

        if game.lastError != nil || !isReady {
            isConfirmingPerson = false
        }

        if phase != .investigation || !isReady {
            dismissARIntroduction()
            endPhotography()
        }

        if phase == .investigation {
            phasePresentation = nil
        } else {
            // A phase always takes precedence over the dismissible evidence sheet.
            // Wait for its native dismissal before presenting the full screen view.
            if isShowingEvidence || evidenceSheetIsActive {
                isShowingEvidence = false
            } else if phasePresentation == nil {
                phasePresentation = GamePhasePresentation()
            }
        }

        updateARInteraction()
        showARIntroductionIfNeeded()
    }

    func phaseScreenDidAppear() {
        isPhaseScreenVisible = true
    }

    func phaseScreenDidDismiss() {
        isPhaseScreenVisible = false
        showARIntroductionIfNeeded()
    }

    func dismissARIntroduction() {
        isShowingARIntroduction = false
    }

    private func showARIntroductionIfNeeded() {
        guard phase == .investigation, isReady, arRuntime.hasCameraFeed,
              !isPhaseScreenVisible, phasePresentation == nil,
              !hasShownARIntroduction,
              arMode == .exploring, !isShowingEvidence, !evidenceSheetIsActive else { return }
        hasShownARIntroduction = true
        isShowingARIntroduction = true
    }

    func beginInvestigation() {
        guard isReady, isHost, phase == .opening else { return }
        game.beginInvestigation()
    }

    func beginPhotography() {
        guard isReady, phase == .investigation, !isShowingEvidence else { return }
        dismissARIntroduction()
        arMode = .photographing
        activeCaptureID = nil
        updateARInteraction()
    }

    func endPhotography() {
        activeCaptureID = nil
        arMode = .exploring
        arRuntime.setPhotographing(false)
    }

    func capturePhoto() {
        guard isReady, phase == .investigation, arMode == .photographing,
              arRuntime.canCapture, !arRuntime.isCapturing,
              let gameID = game.state?.data.id else { return }

        let captureID = UUID()
        activeCaptureID = captureID
        arRuntime.capturePhoto { [weak self] key, image in
            guard let self,
                  self.activeCaptureID == captureID,
                  self.game.state?.data.id == gameID,
                  self.phase == .investigation,
                  self.isReady,
                  self.arMode == .photographing else { return }
            self.game.recordPhoto(image, for: key)
            self.endPhotography()
        }
    }

    func showEvidence() {
        guard isReady, phase == .investigation, arMode == .exploring else { return }
        dismissARIntroduction()
        evidenceSheetIsActive = true
        isShowingEvidence = true
        updateARInteraction()
    }

    func evidenceSheetDidDismiss() {
        isShowingEvidence = false
        evidenceSheetIsActive = false
        synchronize()
    }

    func confirmPerson() {
        guard canConfirmPerson, let selectedPersonID else { return }
        isConfirmingPerson = true
        game.confirmPerson(id: selectedPersonID)
    }

    func submitEvidence() {
        guard canSubmitEvidence, let selectedEvidenceID else { return }
        game.submitEvidence(EvidenceKey(kind: game.myKind, id: selectedEvidenceID))
    }

    func returnToTitle() {
        endPhotography()
        arRuntime.setInteractionEnabled(false)
        game.returnToTitle()
    }

    func stopInteraction() {
        dismissARIntroduction()
        endPhotography()
        arRuntime.setInteractionEnabled(false)
    }

    private func updateARInteraction() {
        let enabled = isReady && phase == .investigation && !isShowingEvidence
            && !evidenceSheetIsActive
        arRuntime.setInteractionEnabled(enabled)
        arRuntime.setPhotographing(enabled && arMode == .photographing)
    }
}
