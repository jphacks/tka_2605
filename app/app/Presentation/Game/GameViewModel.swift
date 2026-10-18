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
    private(set) var isShowingRelocationConfirmation = false

    private var currentGameID: UUID?
    private var hasShownARIntroduction = false
    private var isPhaseScreenVisible = false
    private var currentAttempt: Int?
    private var previousPhase: GamePhase?
    private var evidenceSheetIsActive = false
    private var activeCaptureID: UUID?
    private var searchAssistance = EvidenceSearchAssistance()
    private var relocationConfirmationScope: EvidenceSearchAssistance.Scope?
    private var isGameScreenActive = false
    private var isSceneActive = true
    private let currentTime: () -> TimeInterval

    init(
        game: GameManager? = nil,
        episode: EpisodeManager? = nil,
        arRuntime: EvidenceARRuntime? = nil,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.game = game ?? .shared
        self.episode = episode ?? .shared
        self.arRuntime = arRuntime ?? EvidenceARRuntime()
        self.currentTime = currentTime
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
    var storyPlayback: StoryPlaybackState? { game.state?.storyPlayback }
    var activeStatement: Story.Statement? { game.state?.activeStatement }
    var isShowingStory: Bool { game.state?.hasActiveStory == true }
    var isExploringInvestigation: Bool { phase == .investigation && !isShowingStory }
    var isInvestigationComplete: Bool { game.state?.canAdvanceInvestigation == true }
    var canAdvanceInvestigation: Bool { isReady && isHost && isInvestigationComplete }
    var speakerName: String? {
        guard let statement = activeStatement, statement.personID != 0 else { return nil }
        return game.state?.data.persons.first { $0.id == statement.personID }?.name
    }
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

    private var relocationScope: EvidenceSearchAssistance.Scope? {
        guard isExploringInvestigation, let state = game.state else { return nil }
        return .init(gameID: state.gameID, investigationIndex: state.investigationIndex, kind: game.myKind)
    }

    private var unacquiredEvidenceKeys: Set<EvidenceKey> {
        Set(game.currentInvestigationEvidences.filter {
            !$0.isCollected && photo(for: $0) == nil
        }.map { EvidenceKey(kind: game.myKind, id: $0.id) })
    }

    private var canOfferRelocation: Bool {
        isGameScreenActive && isSceneActive && isReady && isExploringInvestigation
            && arMode == .exploring && arRuntime.hasCameraFeed && !arRuntime.isCapturing
            && !isShowingEvidence && !evidenceSheetIsActive && !isShowingARIntroduction
            && !isPhaseScreenVisible && phasePresentation == nil && !unacquiredEvidenceKeys.isEmpty
    }

    var shouldShowRelocationSuggestion: Bool {
        canOfferRelocation && !isShowingRelocationConfirmation && searchAssistance.shouldSuggest
    }

    var persons: [Person] {
        game.state?.data.persons.filter { $0.id != 0 } ?? []
    }

    var confirmedPersonID: Int? { game.state?.ending.personID }
    var endingStage: EndingStage { game.state?.ending.stage ?? .personSelection }

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
        (game.state?.ending.failedAttempts ?? 0) > 0
    }

    var canConfirmPerson: Bool {
        isReady && isHost && phase == .ending && endingStage == .personSelection && !isShowingStory
            && confirmedPersonID == nil
            && selectedPersonID != nil && !isConfirmingPerson
    }

    var canSubmitEvidence: Bool {
        isReady && phase == .ending && endingStage == .evidenceSelection && !isShowingStory
            && confirmedPersonID != nil
            && selectedEvidenceID != nil && mySubmittedEvidenceID == nil
            && !isSubmittingEvidence
    }

    var canChooseEndingAction: Bool {
        isReady && isHost && phase == .ending && endingStage == .decision && !isShowingStory
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
                evidences: game.currentInvestigationEvidences,
                kind: game.myKind
            )
            if currentAttempt != state.ending.attempt {
                selectedPersonID = nil
                selectedEvidenceID = nil
                isConfirmingPerson = false
                currentAttempt = state.ending.attempt
            }
        }
        updatePhotographedEvidence()

        if previousPhase != phase {
            isConfirmingPerson = false
            previousPhase = phase
        }

        if game.lastError != nil || !isReady {
            isConfirmingPerson = false
        }

        if !isExploringInvestigation || !isReady {
            dismissARIntroduction()
            endPhotography()
        }

        if isExploringInvestigation {
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
        if relocationConfirmationScope != relocationScope || !canOfferRelocation {
            isShowingRelocationConfirmation = false
            relocationConfirmationScope = nil
            updateARInteraction()
        }
        updateSearchAssistance()
    }

    func phaseScreenDidAppear() {
        isPhaseScreenVisible = true
        updateSearchAssistance()
    }

    func phaseScreenDidDismiss() {
        isPhaseScreenVisible = false
        updateARInteraction()
        showARIntroductionIfNeeded()
        updateSearchAssistance()
    }

    func dismissARIntroduction() {
        isShowingARIntroduction = false
        updateSearchAssistance()
    }

    private func showARIntroductionIfNeeded() {
        guard isExploringInvestigation, isReady, arRuntime.hasCameraFeed,
              !isPhaseScreenVisible, phasePresentation == nil,
              !hasShownARIntroduction,
              arMode == .exploring, !isShowingEvidence, !evidenceSheetIsActive else { return }
        hasShownARIntroduction = true
        isShowingARIntroduction = true
    }

    func beginInvestigation() {
        guard isReady, isHost, phase == .opening, !isShowingStory else { return }
        game.beginInvestigation()
    }

    func revealStory(playbackID: UUID) {
        guard isReady, isHost else { return }
        game.revealStory(playbackID: playbackID)
    }

    func advanceStory(playbackID: UUID) {
        guard isReady, isHost else { return }
        game.advanceStory(playbackID: playbackID)
    }

    func advanceInvestigation() {
        guard canAdvanceInvestigation else { return }
        dismissARIntroduction()
        endPhotography()
        game.advanceInvestigation()
    }

    func beginPhotography() {
        guard isReady, isExploringInvestigation, !isShowingEvidence, !isShowingRelocationConfirmation else { return }
        dismissARIntroduction()
        arMode = .photographing
        activeCaptureID = nil
        updateARInteraction()
        updateSearchAssistance()
    }

    func endPhotography() {
        activeCaptureID = nil
        arMode = .exploring
        arRuntime.setPhotographing(false)
        updatePhotographedEvidence()
        updateSearchAssistance()
    }

    func capturePhoto() {
        guard isReady, isExploringInvestigation, arMode == .photographing,
              arRuntime.canCapture, !arRuntime.isCapturing,
              let gameID = game.state?.data.id else { return }

        let captureID = UUID()
        activeCaptureID = captureID
        arRuntime.capturePhoto { [weak self] key, image in
            guard let self,
                  self.activeCaptureID == captureID,
                  self.game.state?.data.id == gameID,
                  self.isExploringInvestigation,
                  self.isReady,
                  self.arMode == .photographing else { return }
            self.game.recordPhoto(image, for: key)
            self.endPhotography()
        }
    }

    func showEvidence() {
        guard isReady, isExploringInvestigation, arMode == .exploring, !isShowingRelocationConfirmation else { return }
        dismissARIntroduction()
        evidenceSheetIsActive = true
        isShowingEvidence = true
        updateARInteraction()
        updateSearchAssistance()
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

    func beginEvidencePresentation() {
        guard canChooseEndingAction else { return }
        game.beginEvidencePresentation()
    }

    func returnToPersonSelection() {
        guard canChooseEndingAction else { return }
        game.returnToPersonSelection()
    }

    func returnToTitle() {
        endPhotography()
        arRuntime.setInteractionEnabled(false)
        game.returnToTitle()
    }

    func stopInteraction() {
        isGameScreenActive = false
        isShowingRelocationConfirmation = false
        relocationConfirmationScope = nil
        dismissARIntroduction()
        endPhotography()
        arRuntime.setInteractionEnabled(false)
        updateSearchAssistance()
    }

    func gameScreenDidAppear(isSceneActive: Bool) {
        isGameScreenActive = true
        self.isSceneActive = isSceneActive
        synchronize()
    }

    func sceneActivityDidChange(isActive: Bool) {
        isSceneActive = isActive
        if !isActive { cancelRelocation() }
        updateARInteraction()
        updateSearchAssistance()
    }

    func runSearchAssistanceTimer() async {
        while !Task.isCancelled {
            updateSearchAssistance()
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
        }
    }

    func updateSearchAssistance() {
        searchAssistance.synchronize(scope: relocationScope, remaining: unacquiredEvidenceKeys)
        searchAssistance.sample(at: currentTime(), isActive: canOfferRelocation && !isShowingRelocationConfirmation)
    }

    func suggestRelocation() {
        guard shouldShowRelocationSuggestion else { return }
        relocationConfirmationScope = relocationScope
        isShowingRelocationConfirmation = true
        updateARInteraction()
        updateSearchAssistance()
    }

    func cancelRelocation() {
        isShowingRelocationConfirmation = false
        relocationConfirmationScope = nil
        updateARInteraction()
        updateSearchAssistance()
    }

    func confirmRelocation() {
        guard isShowingRelocationConfirmation, canOfferRelocation,
              relocationConfirmationScope == relocationScope else {
            cancelRelocation()
            return
        }
        let keys = unacquiredEvidenceKeys
        isShowingRelocationConfirmation = false
        relocationConfirmationScope = nil
        updateARInteraction()
        if arRuntime.relocateUnacquiredEvidence(keys: keys) { searchAssistance.restart() }
        updateSearchAssistance()
    }

    private func updateARInteraction() {
        let enabled = isReady && isGameScreenActive && isSceneActive && isExploringInvestigation && !isShowingEvidence
            && !evidenceSheetIsActive && !isShowingRelocationConfirmation
            && !isPhaseScreenVisible && phasePresentation == nil
        arRuntime.setInteractionEnabled(enabled)
        arRuntime.setPhotographing(enabled && arMode == .photographing)
    }

    private func updatePhotographedEvidence() {
        arRuntime.setPhotographedEvidenceKeys(Set(photographedEvidences.map {
            EvidenceKey(kind: game.myKind, id: $0.id)
        }))
    }
}
