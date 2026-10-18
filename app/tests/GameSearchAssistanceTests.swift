import AppKit
import XCTest
@testable import GameRules

final class GameSearchAssistanceTests: XCTestCase {
    private final class Clock { var time: TimeInterval = 0 }

    @MainActor
    func testSuggestionAfterTenSecondsCancelDoesNotRelocateAndConfirmRestartsCountdown() {
        let clock = Clock()
        let (vm, runtime) = makeViewModel(clock: clock)
        clock.time = 9.999
        vm.updateSearchAssistance()
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        clock.time = 10
        vm.updateSearchAssistance()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
        vm.suggestRelocation()
        XCTAssertTrue(vm.isShowingRelocationConfirmation)
        XCTAssertFalse(runtime.interactionEnabled)
        XCTAssertTrue(runtime.relocationRequests.isEmpty)
        vm.cancelRelocation()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
        XCTAssertTrue(runtime.relocationRequests.isEmpty)
        vm.suggestRelocation()
        vm.confirmRelocation()
        XCTAssertEqual(runtime.relocationRequests, [[key(0), key(1)]])
        XCTAssertTrue(runtime.interactionEnabled)
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        clock.time = 20
        vm.updateSearchAssistance()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
    }

    @MainActor
    func testConfirmedAndPhotographedButUnacknowledgedEvidenceStayUntouched() {
        let clock = Clock()
        var snapshot = investigatingFixture()
        snapshot.data.physicalEvidences.append(Evidence(data: EvidenceData(
            id: 2, storyID: 0, resourceName: "test", name: "Unacquired", description: "", classification: "Floor"
        )))
        XCTAssertTrue(snapshot.apply(.collectEvidence(key(0)), from: .physical))
        let (vm, runtime) = makeViewModel(clock: clock, snapshot: snapshot)
        let confirmedPhoto = NSImage()
        let pendingPhoto = NSImage()
        GameManager.shared.recordPhoto(confirmedPhoto, for: key(0))
        GameManager.shared.recordPhoto(pendingPhoto, for: key(1))
        vm.synchronize()
        XCTAssertFalse(GameManager.shared.state!.evidence(for: key(1))!.isCollected)
        let before = GameManager.shared.state
        let messages = PeerManager.shared.sent
        clock.time = 10
        vm.updateSearchAssistance()
        vm.suggestRelocation()
        vm.confirmRelocation()
        XCTAssertEqual(runtime.relocationRequests, [[key(2)]])
        XCTAssertEqual(GameManager.shared.state, before)
        XCTAssertEqual(PeerManager.shared.sent, messages)
        XCTAssertTrue(EpisodeManager.shared.photo(for: key(0)) === confirmedPhoto)
        XCTAssertTrue(EpisodeManager.shared.photo(for: key(1)) === pendingPhoto)
    }

    @MainActor
    func testNewLocalPhotoRestartsCountdownBeforeHostAcknowledgesIt() {
        let clock = Clock()
        let (vm, _) = makeViewModel(clock: clock)
        clock.time = 6
        vm.updateSearchAssistance()
        GameManager.shared.recordPhoto(NSImage(), for: key(0))
        vm.synchronize()
        clock.time = 15
        vm.updateSearchAssistance()
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        clock.time = 16
        vm.updateSearchAssistance()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
    }

    @MainActor
    func testPhotographyEvidenceSheetAndBackgroundPauseExplorationTime() {
        let clock = Clock()
        let (vm, _) = makeViewModel(clock: clock)
        clock.time = 5
        vm.updateSearchAssistance()
        vm.beginPhotography()
        clock.time = 100
        vm.updateSearchAssistance()
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        vm.endPhotography()
        clock.time = 102
        vm.updateSearchAssistance()
        vm.showEvidence()
        clock.time = 200
        vm.evidenceSheetDidDismiss()
        vm.sceneActivityDidChange(isActive: false)
        clock.time = 300
        vm.sceneActivityDidChange(isActive: true)
        clock.time = 302.999
        vm.updateSearchAssistance()
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        clock.time = 303
        vm.updateSearchAssistance()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
    }

    @MainActor
    func testDisconnectionClosesConfirmationAndPreventsOldConfirmationAction() {
        let clock = Clock()
        let (vm, runtime) = makeViewModel(clock: clock)
        clock.time = 10
        vm.updateSearchAssistance()
        vm.suggestRelocation()
        PeerManager.shared.isConnected = false
        GameManager.shared.connectionDidChange(connected: false)
        vm.synchronize()
        XCTAssertFalse(vm.isShowingRelocationConfirmation)
        vm.confirmRelocation()
        XCTAssertTrue(runtime.relocationRequests.isEmpty)
    }

    @MainActor
    func testPhaseTransitionClosesConfirmationAndDoesNotRelocateNextPhase() {
        let clock = Clock()
        let (vm, runtime) = makeViewModel(clock: clock)
        clock.time = 10
        vm.updateSearchAssistance()
        vm.suggestRelocation()
        var snapshot = GameManager.shared.state!
        snapshot.phase = .ending
        snapshot.revision += 1
        GameManager.shared.receiveSnapshot(snapshot)
        vm.synchronize()
        vm.confirmRelocation()
        XCTAssertFalse(vm.isShowingRelocationConfirmation)
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        XCTAssertTrue(runtime.relocationRequests.isEmpty)
    }

    @MainActor
    func testNoSuggestionWhenAllOwnEvidenceHasLocalPhotosWhileWaitingForPartner() {
        let clock = Clock()
        let (vm, runtime) = makeViewModel(clock: clock)
        for id in 0...1 { GameManager.shared.recordPhoto(NSImage(), for: key(id)) }
        vm.synchronize()
        clock.time = 100
        vm.updateSearchAssistance()
        vm.suggestRelocation()
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        XCTAssertFalse(vm.isShowingRelocationConfirmation)
        XCTAssertTrue(runtime.relocationRequests.isEmpty)
    }

    @MainActor
    func testReturningToGameResumesARWithoutCountingTimeOffscreen() {
        let clock = Clock()
        let (vm, runtime) = makeViewModel(clock: clock)
        clock.time = 5
        vm.updateSearchAssistance()
        vm.stopInteraction()
        XCTAssertFalse(runtime.interactionEnabled)
        clock.time = 100
        vm.gameScreenDidAppear(isSceneActive: true)
        XCTAssertTrue(runtime.interactionEnabled)
        XCTAssertFalse(vm.shouldShowRelocationSuggestion)
        clock.time = 105
        vm.updateSearchAssistance()
        XCTAssertTrue(vm.shouldShowRelocationSuggestion)
    }

    @MainActor
    private func makeViewModel(clock: Clock, snapshot: GameState? = nil) -> (GameViewModel, EvidenceARRuntime) {
        GameManager.shared.returnToTitle()
        PlayerManager.shared.setIsHost(isHost: false)
        PlayerManager.shared.clearOtherPlayers()
        PeerManager.shared.clearSent()
        PeerManager.shared.isConnected = true
        GameManager.shared.connectionDidChange(connected: true)
        GameManager.shared.receiveSnapshot(snapshot ?? investigatingFixture())
        let runtime = EvidenceARRuntime()
        let vm = GameViewModel(arRuntime: runtime, currentTime: { clock.time })
        vm.gameScreenDidAppear(isSceneActive: true)
        vm.dismissARIntroduction()
        return (vm, runtime)
    }

    private func investigatingFixture() -> GameState {
        var state = makeGameStateFixture()
        beginFixtureInvestigation(in: &state)
        return state
    }

    private func key(_ id: Int) -> EvidenceKey { EvidenceKey(kind: .physical, id: id) }
}
