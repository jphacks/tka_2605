import AppKit
import Foundation
import XCTest
@testable import GameRules

final class StoryPlaybackTests: XCTestCase {
    private var game: GameManager { .shared }
    private var peer: PeerManager { .shared }

    override func setUp() {
        super.setUp()
        game.returnToTitle()
        PlayerManager.shared.setIsHost(isHost: false)
        PlayerManager.shared.clearOtherPlayers()
        peer.clearSent()
    }

    override func tearDown() {
        game.returnToTitle()
        peer.clearSent()
        super.tearDown()
    }

    func testOpeningReadsEveryTurnThenFirstInvestigationStoryBeforeExploration() throws {
        var state = makeStoryGameStateFixture()
        XCTAssertTrue(state.start())
        let first = try XCTUnwrap(state.storyPlayback)
        XCTAssertEqual(state.phase, .opening)
        XCTAssertEqual(first.storyID, 10)
        XCTAssertEqual(first.turnIndex, 0)
        XCTAssertEqual(state.activeStatement?.statement, "Opening one")
        XCTAssertEqual(state.activeStatement?.resourceName, "story_10_0")
        assertRejected(.beginInvestigation, from: .personal, in: &state)

        // A natural typing completion sends advance without a forced reveal.
        XCTAssertTrue(state.apply(.advanceStory(playbackID: first.id), from: .personal))
        let second = try XCTUnwrap(state.storyPlayback)
        XCTAssertEqual(state.phase, .opening)
        XCTAssertEqual(second.turnIndex, 1)
        XCTAssertEqual(state.activeStatement?.statement, "Opening two")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(state.apply(.advanceStory(playbackID: second.id), from: .personal))

        let investigation = try XCTUnwrap(state.storyPlayback)
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertEqual(investigation.storyID, 11)
        XCTAssertEqual(state.activeStatement?.statement, "Investigation one")
        XCTAssertFalse(state.canAdvanceInvestigation)
        finishStoryPlayback(in: &state)
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertNil(state.activeStatement)
        XCTAssertEqual(state.currentInvestigationEvidences(for: .personal).map(\.id), [0])
    }

    func testGuestCannotRevealAdvanceOrSkipTheOpening() throws {
        var state = makeStoryGameStateFixture()
        XCTAssertTrue(state.start())
        let playback = try XCTUnwrap(state.storyPlayback)
        assertRejected(.revealStory(playbackID: playback.id), from: .physical, in: &state)
        assertRejected(.advanceStory(playbackID: playback.id), from: .physical, in: &state)
        assertRejected(.beginInvestigation, from: .physical, in: &state)
        assertRejected(.advanceInvestigation(index: 0), from: .physical, in: &state)
    }

    func testFullTextRevealSurvivesSnapshotAndDuplicateOrStaleTapsCannotSkipTurns() throws {
        var state = makeStoryGameStateFixture()
        XCTAssertTrue(state.start())
        let playback = try XCTUnwrap(state.storyPlayback)
        XCTAssertFalse(playback.isTextRevealed)
        XCTAssertTrue(state.apply(.revealStory(playbackID: playback.id), from: .personal))
        XCTAssertEqual(state.storyPlayback?.isTextRevealed, true)
        XCTAssertEqual(state.storyPlayback?.turnIndex, 0)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.storyPlayback?.id, playback.id)
        XCTAssertEqual(restored.activeStatement?.statement, "Opening one")
        assertRejected(.revealStory(playbackID: playback.id), from: .personal, in: &state)

        XCTAssertTrue(state.apply(.advanceStory(playbackID: playback.id), from: .personal))
        XCTAssertEqual(state.storyPlayback?.turnIndex, 1)
        XCTAssertEqual(state.storyPlayback?.isTextRevealed, false)
        assertRejected(.advanceStory(playbackID: playback.id), from: .personal, in: &state)
        assertRejected(.revealStory(playbackID: playback.id), from: .personal, in: &state)
        assertRejected(.advanceStory(playbackID: UUID()), from: .personal, in: &state)
    }

    func testInvestigationStoryBlocksCollectionUntilItsLastStatementIsRead() throws {
        var state = makeStoryGameStateFixture()
        XCTAssertTrue(state.start())
        for _ in 0..<2 {
            let playback = try XCTUnwrap(state.storyPlayback)
            XCTAssertTrue(state.apply(.advanceStory(playbackID: playback.id), from: .personal))
        }
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertTrue(state.hasActiveStory)
        assertRejected(.collectEvidence(key(.personal, 0)), from: .personal, in: &state)
        assertRejected(.collectEvidence(key(.physical, 0)), from: .physical, in: &state)
        assertRejected(.advanceInvestigation(index: 0), from: .personal, in: &state)
        finishStoryPlayback(in: &state)
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        XCTAssertEqual(state.totalCollectedCount, 1)
    }

    func testBothPlayersMustFinishEachStageAndHostExplicitlyAdvancesOnlyOnce() {
        var state = makeStoryGameStateFixture()
        beginFixtureInvestigation(in: &state)
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        XCTAssertFalse(state.canAdvanceInvestigation)
        assertRejected(.advanceInvestigation(index: 0), from: .personal, in: &state)
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 0)), from: .physical))
        XCTAssertTrue(state.canAdvanceInvestigation)
        XCTAssertEqual(state.investigationIndex, 0)
        XCTAssertEqual(state.currentStory?.id, 11)
        assertRejected(.advanceInvestigation(index: 0), from: .physical, in: &state)
        assertRejected(.advanceInvestigation(index: 1), from: .personal, in: &state)

        XCTAssertTrue(state.apply(.advanceInvestigation(index: 0), from: .personal))
        XCTAssertEqual(state.investigationIndex, 1)
        XCTAssertEqual(state.storyPlayback?.storyID, 12)
        XCTAssertFalse(state.canAdvanceInvestigation)
        assertRejected(.advanceInvestigation(index: 0), from: .personal, in: &state)
        assertRejected(.collectEvidence(key(.physical, 1)), from: .physical, in: &state)
        finishStoryPlayback(in: &state)
        collectCurrentStage(in: &state)
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertTrue(state.canAdvanceInvestigation)
        assertRejected(.advanceInvestigation(index: 0), from: .personal, in: &state)
        XCTAssertTrue(state.apply(.advanceInvestigation(index: 1), from: .personal))
        XCTAssertEqual(state.phase, .ending)
    }

    func testEndingReadsOnlySelectedPersonsTurnsThenOffersDecision() throws {
        var state = endingStateWithStories()
        XCTAssertEqual(state.ending.stage, .personSelection)
        XCTAssertFalse(state.hasActiveStory)
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        XCTAssertEqual(state.ending.stage, .testimony)
        XCTAssertEqual(state.storyPlayback?.turnIndex, 1)
        XCTAssertEqual(state.activeStatement?.statement, "Selected first")
        assertRejected(.beginEvidencePresentation(attempt: 0), from: .personal, in: &state)
        assertRejected(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal, in: &state)

        let first = try XCTUnwrap(state.storyPlayback)
        XCTAssertTrue(state.apply(.advanceStory(playbackID: first.id), from: .personal))
        XCTAssertEqual(state.storyPlayback?.turnIndex, 3)
        XCTAssertEqual(state.activeStatement?.statement, "Selected second")
        let second = try XCTUnwrap(state.storyPlayback)
        XCTAssertTrue(state.apply(.advanceStory(playbackID: second.id), from: .personal))
        XCTAssertFalse(state.hasActiveStory)
        XCTAssertEqual(state.ending.stage, .decision)
        assertRejected(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical, in: &state)
        assertRejected(.beginEvidencePresentation(attempt: 0), from: .physical, in: &state)
        XCTAssertTrue(state.apply(.beginEvidencePresentation(attempt: 0), from: .personal))
        XCTAssertEqual(state.ending.stage, .evidenceSelection)
        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical))
    }

    func testReturningFromDecisionRestartsSelectionWithoutCountingAnIncorrectAnswer() throws {
        var state = endingStateWithStories()
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        let previousPlayback = try XCTUnwrap(state.storyPlayback)
        finishStoryPlayback(in: &state)
        assertRejected(.returnToPersonSelection(attempt: 0), from: .physical, in: &state)
        XCTAssertTrue(state.apply(.returnToPersonSelection(attempt: 0), from: .personal))
        XCTAssertEqual(state.ending, EndingState(attempt: 1))
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(state.totalCollectedCount, state.totalEvidenceCount)
        assertRejected(.selectPerson(id: 3, attempt: 0), from: .personal, in: &state)
        assertRejected(.beginEvidencePresentation(attempt: 0), from: .personal, in: &state)
        assertRejected(.returnToPersonSelection(attempt: 0), from: .personal, in: &state)

        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 1), from: .personal))
        XCTAssertNotEqual(state.storyPlayback?.id, previousPlayback.id)
        assertRejected(.advanceStory(playbackID: previousPlayback.id), from: .personal, in: &state)
    }

    func testIncorrectAnswerResetsEveryoneAndBackNavigationPreservesFailureCount() {
        var state = endingStateWithStories()
        XCTAssertTrue(state.apply(.selectPerson(id: 4, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical))
        XCTAssertEqual(state.ending, EndingState(attempt: 1, failedAttempts: 1))
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 1), from: .personal))
        finishStoryPlayback(in: &state)
        XCTAssertTrue(state.apply(.returnToPersonSelection(attempt: 1), from: .personal))
        XCTAssertEqual(state.ending, EndingState(attempt: 2, failedAttempts: 1))
    }

    func testCorrectAnswerPlaysEveryResultTurnBeforeStaticClearScreen() throws {
        var state = endingStateWithStories()
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical))
        XCTAssertEqual(state.phase, .ending)
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        XCTAssertEqual(state.phase, .cleared)
        XCTAssertEqual(state.storyPlayback?.storyID, 14)
        XCTAssertEqual(state.activeStatement?.statement, "Case solved")
        let first = try XCTUnwrap(state.storyPlayback)
        assertRejected(.advanceStory(playbackID: first.id), from: .physical, in: &state)
        XCTAssertTrue(state.apply(.advanceStory(playbackID: first.id), from: .personal))
        XCTAssertEqual(state.activeStatement?.statement, "Explanation")
        finishStoryPlayback(in: &state)
        XCTAssertEqual(state.phase, .cleared)
        XCTAssertFalse(state.hasActiveStory)
        XCTAssertNil(state.activeStatement)
        assertRejected(.selectPerson(id: 4, attempt: 0), from: .personal, in: &state)
    }

    func testGuestManagerCannotSendHostStoryOrDecisionActions() throws {
        var snapshot = makeStoryGameStateFixture()
        XCTAssertTrue(snapshot.start())
        connectGuest(to: snapshot)
        let playback = try XCTUnwrap(snapshot.storyPlayback)
        peer.clearSent()
        game.revealStory(playbackID: playback.id)
        game.advanceStory(playbackID: playback.id)
        game.advanceInvestigation()
        game.confirmPerson(id: 3)
        game.beginEvidencePresentation()
        game.returnToPersonSelection()
        XCTAssertEqual(game.state, snapshot)
        XCTAssertTrue(peer.sent.isEmpty)
    }

    func testHostManagerRejectsGuestStoryRequestsAndBroadcastsRevealedState() throws {
        startHostGame()
        let before = try XCTUnwrap(game.state)
        let playback = try XCTUnwrap(before.storyPlayback)
        peer.clearSent()
        game.receiveAction(.revealStory(playbackID: playback.id), gameID: before.gameID, messageID: UUID())
        game.receiveAction(.advanceStory(playbackID: playback.id), gameID: before.gameID, messageID: UUID())
        XCTAssertEqual(game.state, before)
        XCTAssertEqual(peer.sent.count, 2)
        game.revealStory(playbackID: playback.id)
        XCTAssertEqual(game.state?.storyPlayback?.isTextRevealed, true)
        guard case .stateSnapshot(let shared)? = peer.sent.last?.payload else {
            return XCTFail("The full-text reveal must be shared with the guest")
        }
        XCTAssertEqual(shared, game.state)
        game.advanceStory(playbackID: playback.id)
        let next = try XCTUnwrap(game.state)
        game.advanceStory(playbackID: playback.id)
        XCTAssertEqual(game.state, next)
    }

    @MainActor
    func testProgressButtonIsAvailableOnlyToReadyHostAfterBothPlayersFinish() throws {
        startHostGame()
        while let playback = game.state?.storyPlayback { game.advanceStory(playbackID: playback.id) }
        let vm = GameViewModel(arRuntime: EvidenceARRuntime())
        XCTAssertFalse(vm.canAdvanceInvestigation)
        game.recordPhoto(NSImage(), for: key(.personal, 0))
        XCTAssertFalse(vm.canAdvanceInvestigation)
        let gameID = try XCTUnwrap(game.state).gameID
        game.receiveAction(.collectEvidence(key(.physical, 0)), gameID: gameID, messageID: UUID())
        XCTAssertTrue(vm.canAdvanceInvestigation)
        XCTAssertEqual(game.state?.investigationIndex, 0)
        PlayerManager.shared.setIsHost(isHost: false)
        XCTAssertFalse(vm.canAdvanceInvestigation)
        PlayerManager.shared.setIsHost(isHost: true)
        peer.isConnected = false
        game.connectionDidChange(connected: false)
        XCTAssertFalse(vm.canAdvanceInvestigation)
    }

    @MainActor
    func testStoryInterruptsEvidenceSheetThenReturnsToSameARRuntimeAndKeepsPhoto() throws {
        var snapshot = makeStoryGameStateFixture()
        beginFixtureInvestigation(in: &snapshot)
        connectGuest(to: snapshot)
        let runtime = EvidenceARRuntime()
        let vm = GameViewModel(arRuntime: runtime)
        vm.gameScreenDidAppear(isSceneActive: true)
        vm.dismissARIntroduction()
        let image = NSImage()
        game.recordPhoto(image, for: key(.physical, 0))
        vm.showEvidence()
        XCTAssertTrue(vm.isShowingEvidence)
        collectCurrentStage(in: &snapshot)
        XCTAssertTrue(snapshot.apply(.advanceInvestigation(index: 0), from: .personal))
        game.receiveSnapshot(snapshot)
        vm.synchronize()
        XCTAssertFalse(vm.isShowingEvidence)
        XCTAssertFalse(runtime.interactionEnabled)
        XCTAssertNil(vm.phasePresentation, "The native evidence sheet must dismiss first")
        vm.evidenceSheetDidDismiss()
        XCTAssertNotNil(vm.phasePresentation)
        vm.phaseScreenDidAppear()
        game.recordPhoto(NSImage(), for: key(.physical, 1))
        XCTAssertNil(EpisodeManager.shared.photo(for: key(.physical, 1)))

        let playback = try XCTUnwrap(snapshot.storyPlayback)
        XCTAssertTrue(snapshot.apply(.revealStory(playbackID: playback.id), from: .personal))
        peer.isConnected = false
        game.connectionDidChange(connected: false)
        connectGuest(to: snapshot)
        vm.synchronize()
        XCTAssertEqual(game.state?.storyPlayback, snapshot.storyPlayback)
        XCTAssertTrue(EpisodeManager.shared.photo(for: key(.physical, 0)) === image)
        finishStoryPlayback(in: &snapshot)
        game.receiveSnapshot(snapshot)
        vm.synchronize()
        XCTAssertNil(vm.phasePresentation)
        vm.phaseScreenDidDismiss()
        vm.dismissARIntroduction()
        XCTAssertTrue(runtime.interactionEnabled)
        XCTAssertTrue(vm.arRuntime === runtime)
        XCTAssertTrue(EpisodeManager.shared.photo(for: key(.physical, 0)) === image)
    }

    private func endingStateWithStories() -> GameState {
        var state = makeStoryGameStateFixture()
        state.data.stories.append(Story(data: StoryData(
            id: 13, tag: StoryTag.truthUncovering.rawValue,
            turn: [
                StatementData(personID: 4, resourceName: "other", statement: "Other first"),
                StatementData(personID: 3, resourceName: "selected_1", statement: "Selected first"),
                StatementData(personID: 4, resourceName: "other", statement: "Other second"),
                StatementData(personID: 3, resourceName: "selected_2", statement: "Selected second")
            ]
        )))
        state.data.stories.append(makeStoryFixture(id: 14, tag: .result, statements: ["Case solved", "Explanation"]))
        beginFixtureInvestigation(in: &state)
        for index in 0..<2 {
            collectCurrentStage(in: &state)
            XCTAssertTrue(state.apply(.advanceInvestigation(index: index), from: .personal))
            finishStoryPlayback(in: &state)
        }
        XCTAssertEqual(state.phase, .ending)
        return state
    }

    private func collectCurrentStage(in state: inout GameState) {
        for kind in EvidenceKind.allCases {
            for evidence in state.currentInvestigationEvidences(for: kind) where !evidence.isCollected {
                XCTAssertTrue(state.apply(.collectEvidence(key(kind, evidence.id)), from: kind))
            }
        }
    }

    private func connectGuest(to snapshot: GameState) {
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        game.receiveSnapshot(snapshot)
        XCTAssertTrue(game.isReady)
    }

    private func startHostGame() {
        let lobby = makeStoryGameStateFixture()
        PlayerManager.shared.setIsHost(isHost: true)
        EpisodeManager.shared.applyGameState(lobby)
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        game.receiveAcknowledgement(gameID: lobby.gameID, revision: lobby.revision)
        game.startGame()
        XCTAssertEqual(game.phase, .opening)
    }

    private func assertRejected(
        _ action: PlayerAction,
        from actor: EvidenceKind,
        in state: inout GameState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = state
        XCTAssertFalse(state.apply(action, from: actor), file: file, line: line)
        XCTAssertEqual(state, before, "A rejected action must leave shared state untouched", file: file, line: line)
    }

    private func key(_ kind: EvidenceKind, _ id: Int) -> EvidenceKey {
        EvidenceKey(kind: kind, id: id)
    }
}
