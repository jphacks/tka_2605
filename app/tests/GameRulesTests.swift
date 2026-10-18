import XCTest
@testable import GameRules

final class GameRulesTests: XCTestCase {
    func testStartRequiresValidEpisodeAndOnlyHostCanBeginInvestigation() {
        var state = makeState()
        XCTAssertTrue(state.start())
        XCTAssertEqual(state.phase, .opening)
        XCTAssertEqual(state.revision, 1)

        assertRejected(.beginInvestigation, from: .physical, state: &state)
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal))
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertEqual(state.revision, 2)
        XCTAssertFalse(state.start())
        assertRejected(.beginInvestigation, from: .personal, state: &state)
    }

    func testStartRejectsMissingOrInvalidSolution() {
        var state = makeState()
        state.data.keyPersonalEvidenceID = nil
        XCTAssertFalse(state.start())
        XCTAssertNil(state.phase)
        XCTAssertEqual(state.revision, 0)

        state = makeState()
        state.data.keyPhysicalEvidenceID = 999
        XCTAssertFalse(state.start())

        state = makeState()
        state.data.keyPersonID = 0
        XCTAssertFalse(state.start())

        state = makeState()
        state.data.physicalEvidences = []
        XCTAssertFalse(state.start())
    }

    func testCollectionRejectsWrongRoleUnknownEvidenceAndWrongPhase() {
        var state = makeState()
        assertRejected(.collectEvidence(key(.personal, 0)), from: .personal, state: &state)
        XCTAssertTrue(state.start())
        assertRejected(.collectEvidence(key(.personal, 0)), from: .personal, state: &state)
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal))

        assertRejected(.collectEvidence(key(.physical, 0)), from: .personal, state: &state)
        assertRejected(.collectEvidence(key(.personal, 0)), from: .physical, state: &state)
        assertRejected(.collectEvidence(key(.personal, 999)), from: .personal, state: &state)
    }

    func testSameNumericIDInDifferentKindsIsCollectedIndependently() {
        var state = makeInvestigatingState()
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        XCTAssertEqual(state.evidence(for: key(.personal, 0))?.isCollected, true)
        XCTAssertEqual(state.evidence(for: key(.physical, 0))?.isCollected, false)
        XCTAssertEqual(state.totalCollectedCount, 1)

        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 0)), from: .physical))
        XCTAssertEqual(state.totalCollectedCount, 2)
    }

    func testDuplicateCollectionDoesNotChangeStateOrRevision() {
        var state = makeInvestigatingState()
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        assertRejected(.collectEvidence(key(.personal, 0)), from: .personal, state: &state)
        XCTAssertEqual(state.totalCollectedCount, 1)
    }

    func testEndingRequiresBothRolesToCollectEveryEvidenceAndHostToAdvance() {
        var state = makeInvestigatingState()
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        XCTAssertTrue(state.apply(.collectEvidence(key(.personal, 1)), from: .personal))
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 0)), from: .physical))
        XCTAssertEqual(state.totalCollectedCount, 3)
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertFalse(state.canAdvanceInvestigation)
        assertRejected(.advanceInvestigation(index: state.investigationIndex), from: .personal, state: &state)

        let revision = state.revision
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 1)), from: .physical))
        XCTAssertEqual(state.totalCollectedCount, state.totalEvidenceCount)
        XCTAssertEqual(state.phase, .investigation)
        XCTAssertEqual(state.revision, revision + 1)
        XCTAssertTrue(state.canAdvanceInvestigation)
        assertRejected(.advanceInvestigation(index: state.investigationIndex), from: .physical, state: &state)
        XCTAssertTrue(state.apply(.advanceInvestigation(index: state.investigationIndex), from: .personal))
        XCTAssertEqual(state.phase, .ending)
        assertRejected(.collectEvidence(key(.personal, 0)), from: .personal, state: &state)
    }

    func testOnlyHostCanSelectAnExistingNonNarratorOncePerAttempt() {
        var state = makeInvestigatingState()
        assertRejected(.selectPerson(id: 3, attempt: 0), from: .personal, state: &state)
        collectAll(in: &state)
        assertRejected(.selectPerson(id: 3, attempt: 0), from: .physical, state: &state)
        assertRejected(.selectPerson(id: 0, attempt: 0), from: .personal, state: &state)
        assertRejected(.selectPerson(id: 999, attempt: 0), from: .personal, state: &state)

        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        assertRejected(.selectPerson(id: 4, attempt: 0), from: .personal, state: &state)
        XCTAssertEqual(state.ending.personID, 3)
    }

    func testSubmissionRequiresSelectedPersonMatchingRoleAndExistingEvidence() {
        var state = makeEndingState()
        assertRejected(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal, state: &state)
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        assertRejected(.submitEvidence(key(.physical, 1), attempt: 0), from: .personal, state: &state)
        assertRejected(.submitEvidence(key(.personal, 0), attempt: 0), from: .physical, state: &state)
        assertRejected(.submitEvidence(key(.physical, 999), attempt: 0), from: .physical, state: &state)
    }

    func testOneCorrectSubmissionWaitsForTheOtherPlayerAndCannotBeReplaced() {
        var state = makeEndingState()
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(state.ending.hostEvidenceID, 0)
        XCTAssertNil(state.ending.guestEvidenceID)
        assertRejected(.submitEvidence(key(.personal, 1), attempt: 0), from: .personal, state: &state)
    }

    func testCorrectPersonAndBothCorrectEvidencesClearInEitherSubmissionOrder() {
        for guestFirst in [false, true] {
            var state = makeEndingState()
            XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
            beginFixtureEvidencePresentation(in: &state)
            let submissions: [(EvidenceKind, Int)] = guestFirst
                ? [(.physical, 1), (.personal, 0)]
                : [(.personal, 0), (.physical, 1)]

            for (kind, id) in submissions {
                XCTAssertTrue(state.apply(.submitEvidence(key(kind, id), attempt: 0), from: kind))
            }

            XCTAssertEqual(state.phase, .cleared)
            XCTAssertEqual(state.ending.attempt, 0)
            assertRejected(.selectPerson(id: 3, attempt: 0), from: .personal, state: &state)
            assertRejected(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical, state: &state)
        }
    }

    func testWrongPersonOrEitherWrongEvidenceResetsBothPlayersForNextAttempt() {
        let incorrectAnswers = [(4, 0, 1), (3, 1, 1), (3, 0, 0)]
        for (personID, personalID, physicalID) in incorrectAnswers {
            var state = makeEndingState()
            XCTAssertTrue(state.apply(.selectPerson(id: personID, attempt: 0), from: .personal))
            beginFixtureEvidencePresentation(in: &state)
            XCTAssertTrue(state.apply(.submitEvidence(key(.personal, personalID), attempt: 0), from: .personal))
            XCTAssertEqual(state.ending.attempt, 0, "Wait until both players submit before judging")
            XCTAssertTrue(state.apply(.submitEvidence(key(.physical, physicalID), attempt: 0), from: .physical))

            XCTAssertEqual(state.phase, .ending)
            XCTAssertEqual(state.ending, EndingState(attempt: 1, failedAttempts: 1))
            XCTAssertEqual(state.totalCollectedCount, state.totalEvidenceCount)
        }
    }

    func testStaleAndFutureAttemptActionsAreRejectedAndNewAttemptCanClear() {
        var state = makeEndingState()
        XCTAssertTrue(state.apply(.selectPerson(id: 4, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical))
        XCTAssertEqual(state.ending.attempt, 1)

        assertRejected(.selectPerson(id: 3, attempt: 0), from: .personal, state: &state)
        assertRejected(.selectPerson(id: 3, attempt: 2), from: .personal, state: &state)
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 1), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        assertRejected(.submitEvidence(key(.physical, 1), attempt: 0), from: .physical, state: &state)
        assertRejected(.submitEvidence(key(.personal, 0), attempt: 2), from: .personal, state: &state)

        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 1), attempt: 1), from: .physical))
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 1), from: .personal))
        XCTAssertEqual(state.phase, .cleared)
    }

    func testGameStateAndEveryActionRoundTripThroughJSON() throws {
        var state = makeEndingState()
        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        beginFixtureEvidencePresentation(in: &state)
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(GameState.self, from: encoder.encode(state)), state)

        let actions: [PlayerAction] = [
            .beginInvestigation,
            .revealStory(playbackID: UUID()),
            .advanceStory(playbackID: UUID()),
            .advanceInvestigation(index: 2),
            .beginEvidencePresentation(attempt: 7),
            .returnToPersonSelection(attempt: 7),
            .collectEvidence(key(.personal, 0)),
            .collectEvidence(key(.physical, 0)),
            .selectPerson(id: 3, attempt: 7),
            .submitEvidence(key(.personal, 0), attempt: 7),
            .submitEvidence(key(.physical, 1), attempt: 7)
        ]
        for action in actions {
            XCTAssertEqual(try decoder.decode(PlayerAction.self, from: encoder.encode(action)), action)
        }
    }

    private func key(_ kind: EvidenceKind, _ id: Int) -> EvidenceKey {
        EvidenceKey(kind: kind, id: id)
    }

    private func assertRejected(
        _ action: PlayerAction,
        from actor: EvidenceKind,
        state: inout GameState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = state
        XCTAssertFalse(state.apply(action, from: actor), file: file, line: line)
        XCTAssertEqual(state, before, "Rejected actions must leave all state unchanged", file: file, line: line)
    }

    private func makeInvestigatingState() -> GameState {
        var state = makeState()
        beginFixtureInvestigation(in: &state)
        return state
    }

    private func makeEndingState() -> GameState {
        var state = makeInvestigatingState()
        collectAll(in: &state)
        return state
    }

    private func collectAll(in state: inout GameState) {
        for kind in EvidenceKind.allCases {
            for evidence in state.evidences(for: kind) {
                XCTAssertTrue(state.apply(.collectEvidence(key(kind, evidence.id)), from: kind))
            }
        }
        XCTAssertTrue(state.canAdvanceInvestigation)
        XCTAssertTrue(state.apply(.advanceInvestigation(index: state.investigationIndex), from: .personal))
        XCTAssertEqual(state.phase, .ending)
    }

    private func makeState() -> GameState {
        makeGameStateFixture()
    }
}
