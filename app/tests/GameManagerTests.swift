import AppKit
import Foundation
import XCTest
@testable import GameRules

final class GameManagerTests: XCTestCase {
    private var game: GameManager { .shared }
    private var peer: PeerManager { .shared }
    private let guestKey = EvidenceKey(kind: .physical, id: 1)

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

    func testGuestInitialSnapshotAcknowledgesExactStateAndOpensGame() {
        let snapshot = investigatingFixture()
        connectGuest(to: snapshot)

        XCTAssertEqual(game.state, snapshot)
        XCTAssertEqual(EpisodeManager.shared.data, snapshot.data)
        XCTAssertTrue(game.isReady)
        XCTAssertEqual(ScreenManager.shared.mainScreenState, .Game)
        XCTAssertEqual(peer.sent.map(\.payload), [
            .snapshotAcknowledgement(gameID: snapshot.gameID, revision: snapshot.revision)
        ])
    }

    func testHostWaitsForMatchingAcknowledgementBeforeStartingBothPhases() throws {
        let lobby = makeGameStateFixture()
        PlayerManager.shared.setIsHost(isHost: true)
        EpisodeManager.shared.applyGameState(lobby)
        peer.isConnected = true
        game.connectionDidChange(connected: true)

        XCTAssertFalse(game.isReady)
        XCTAssertEqual(peer.sent.map(\.payload), [.stateSnapshot(state: lobby)])
        game.startGame()
        XCTAssertNil(game.phase)

        game.receiveAcknowledgement(gameID: UUID(), revision: lobby.revision)
        game.receiveAcknowledgement(gameID: lobby.gameID, revision: lobby.revision + 1)
        XCTAssertFalse(game.isReady)
        game.receiveAcknowledgement(gameID: lobby.gameID, revision: lobby.revision)
        XCTAssertTrue(game.isReady)

        peer.clearSent()
        game.startGame()
        XCTAssertEqual(game.phase, .opening)
        XCTAssertEqual(try lastSnapshot().phase, .opening)
        game.beginInvestigation()
        XCTAssertEqual(game.phase, .investigation)
        XCTAssertEqual(try lastSnapshot(), game.state)
        XCTAssertEqual(peer.sent.count, 2)
    }

    func testUnconfirmedCollectionReplaysWithSameIDAfterReconnectThenStopsAfterConfirmation() throws {
        let snapshot = investigatingFixture()
        connectGuest(to: snapshot)
        peer.clearSent()
        let image = NSImage(size: NSSize(width: 16, height: 16))
        game.recordPhoto(image, for: guestKey)
        let original = try XCTUnwrap(playerActions().first)
        XCTAssertEqual(original.payload, .playerAction(gameID: snapshot.gameID, action: .collectEvidence(guestKey)))
        XCTAssertEqual(game.myCollectedCount, 0, "Only the host confirms collection")

        disconnect()
        XCTAssertFalse(game.isReady)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)
        peer.clearSent()
        game.recordPhoto(NSImage(), for: guestKey)
        XCTAssertTrue(peer.sent.isEmpty)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)

        reconnectGuest(to: snapshot)
        XCTAssertEqual(peer.sent.map(\.kind), [.snapshotAcknowledgement, .playerAction])
        XCTAssertEqual(playerActions().first?.id, original.id)
        XCTAssertEqual(playerActions().first?.payload, original.payload)

        var confirmed = snapshot
        XCTAssertTrue(confirmed.apply(.collectEvidence(guestKey), from: .physical))
        game.receiveSnapshot(confirmed)
        XCTAssertEqual(game.myCollectedCount, 1)
        disconnect()
        peer.clearSent()
        reconnectGuest(to: confirmed)
        XCTAssertTrue(playerActions().isEmpty, "A confirmed collection must leave the resend queue")
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)
    }

    func testCollectionAlreadyAcceptedBeforeDisconnectDoesNotReplayAndKeepsPhoto() {
        var authoritative = investigatingFixture()
        connectGuest(to: authoritative)
        let image = NSImage()
        game.recordPhoto(image, for: guestKey)
        disconnect()

        XCTAssertTrue(authoritative.apply(.collectEvidence(guestKey), from: .physical))
        peer.clearSent()
        reconnectGuest(to: authoritative)
        XCTAssertTrue(playerActions().isEmpty)
        XCTAssertEqual(game.myCollectedCount, 1)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)
    }

    func testRetakingConfirmedEvidenceReplacesPhotoWithoutAnotherCollection() {
        var snapshot = investigatingFixture()
        XCTAssertTrue(snapshot.apply(.collectEvidence(guestKey), from: .physical))
        connectGuest(to: snapshot)
        peer.clearSent()

        let first = NSImage()
        let second = NSImage()
        game.recordPhoto(first, for: guestKey)
        game.recordPhoto(second, for: guestKey)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === second)
        XCTAssertTrue(playerActions().isEmpty)
        XCTAssertEqual(game.myCollectedCount, 1)
        XCTAssertEqual(game.state, snapshot)
    }

    func testPendingSubmissionReplaysOncePerReconnectAndClearsWhenConfirmed() throws {
        var snapshot = endingFixture()
        XCTAssertTrue(snapshot.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        connectGuest(to: snapshot)
        peer.clearSent()
        game.submitEvidence(guestKey)
        let original = try XCTUnwrap(playerActions().first)
        XCTAssertEqual(game.myPendingEvidenceID, guestKey.id)

        game.submitEvidence(EvidenceKey(kind: .physical, id: 0))
        XCTAssertEqual(playerActions().count, 1, "Pending submissions cannot be replaced")
        disconnect()
        peer.clearSent()
        reconnectGuest(to: snapshot)
        XCTAssertEqual(playerActions().count, 1)
        XCTAssertEqual(playerActions().first?.id, original.id)
        XCTAssertEqual(playerActions().first?.payload, original.payload)

        XCTAssertTrue(snapshot.apply(.submitEvidence(guestKey, attempt: 0), from: .physical))
        game.receiveSnapshot(snapshot)
        XCTAssertNil(game.myPendingEvidenceID)
        disconnect()
        peer.clearSent()
        reconnectGuest(to: snapshot)
        XCTAssertTrue(playerActions().isEmpty)
    }

    func testNewEndingAttemptDiscardsOldPendingSubmissionAndAllowsNewAnswer() throws {
        var snapshot = endingFixture()
        XCTAssertTrue(snapshot.apply(.selectPerson(id: 4, attempt: 0), from: .personal))
        connectGuest(to: snapshot)
        peer.clearSent()
        game.submitEvidence(guestKey)
        let oldID = try XCTUnwrap(playerActions().first?.id)
        disconnect()

        XCTAssertTrue(snapshot.apply(.submitEvidence(EvidenceKey(kind: .personal, id: 0), attempt: 0), from: .personal))
        XCTAssertTrue(snapshot.apply(.submitEvidence(guestKey, attempt: 0), from: .physical))
        XCTAssertEqual(snapshot.ending.attempt, 1)
        peer.clearSent()
        reconnectGuest(to: snapshot)
        XCTAssertNil(game.myPendingEvidenceID)
        XCTAssertTrue(playerActions().isEmpty, "The previous attempt's submission must never be replayed")

        XCTAssertTrue(snapshot.apply(.selectPerson(id: 3, attempt: 1), from: .personal))
        game.receiveSnapshot(snapshot)
        peer.clearSent()
        game.submitEvidence(guestKey)
        let newMessage = try XCTUnwrap(playerActions().first)
        XCTAssertNotEqual(newMessage.id, oldID)
        XCTAssertEqual(newMessage.payload, .playerAction(
            gameID: snapshot.gameID, action: .submitEvidence(guestKey, attempt: 1)
        ))
    }

    func testStaleSnapshotCannotRollBackConfirmedCollectionOrPhoto() {
        let old = investigatingFixture()
        var current = old
        XCTAssertTrue(current.apply(.collectEvidence(guestKey), from: .physical))
        connectGuest(to: current)
        let image = NSImage()
        EpisodeManager.shared.savePhoto(image, for: guestKey)
        peer.clearSent()

        game.receiveSnapshot(old)
        XCTAssertEqual(game.state, current)
        XCTAssertEqual(EpisodeManager.shared.data, current.data)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)
        XCTAssertEqual(peer.sent.map(\.payload), [
            .snapshotAcknowledgement(gameID: current.gameID, revision: current.revision)
        ])
    }

    func testDifferentGameSnapshotIsRejectedDuringActiveGame() {
        let active = investigatingFixture()
        connectGuest(to: active)
        let image = NSImage()
        EpisodeManager.shared.savePhoto(image, for: guestKey)
        peer.clearSent()

        game.receiveSnapshot(investigatingFixture())
        XCTAssertEqual(game.state, active)
        XCTAssertTrue(peer.sent.isEmpty)
        XCTAssertTrue(EpisodeManager.shared.photo(for: guestKey) === image)
    }

    func testNewGameInLobbyClearsPhotosFromPreviousGame() {
        let first = makeGameStateFixture()
        connectGuest(to: first)
        EpisodeManager.shared.savePhoto(NSImage(), for: guestKey)
        let second = makeGameStateFixture()
        game.receiveSnapshot(second)

        XCTAssertEqual(game.state, second)
        XCTAssertNil(EpisodeManager.shared.photo(for: guestKey))
    }

    func testHostDeduplicatesRemoteCollectionAndStillReturnsAuthoritativeSnapshot() throws {
        makeHostInvestigating()
        let before = try XCTUnwrap(game.state)
        let id = UUID()
        peer.clearSent()
        game.receiveAction(.collectEvidence(guestKey), gameID: before.gameID, messageID: id)
        let confirmed = try XCTUnwrap(game.state)
        XCTAssertEqual(confirmed.totalCollectedCount, before.totalCollectedCount + 1)
        XCTAssertEqual(confirmed.revision, before.revision + 1)

        game.receiveAction(.collectEvidence(guestKey), gameID: before.gameID, messageID: id)
        XCTAssertEqual(game.state, confirmed)
        XCTAssertEqual(peer.sent.count, 2)
        XCTAssertEqual(try lastSnapshot(), confirmed)

        game.receiveAction(.collectEvidence(EvidenceKey(kind: .personal, id: 0)), gameID: before.gameID, messageID: UUID())
        XCTAssertEqual(game.state, confirmed)
        XCTAssertEqual(try lastSnapshot(), confirmed)
        let count = peer.sent.count
        game.receiveAction(.collectEvidence(guestKey), gameID: UUID(), messageID: UUID())
        XCTAssertEqual(peer.sent.count, count, "An action from another game must be ignored")
    }

    func testHostRejectsPreviousAttemptSubmissionThenCompletesNewAttempt() throws {
        makeHostInvestigating()
        for id in 0...1 {
            game.recordPhoto(NSImage(), for: EvidenceKey(kind: .personal, id: id))
            game.receiveAction(.collectEvidence(EvidenceKey(kind: .physical, id: id)), gameID: try XCTUnwrap(game.state).gameID, messageID: UUID())
        }
        XCTAssertEqual(game.phase, .ending)
        game.confirmPerson(id: 4)
        game.submitEvidence(EvidenceKey(kind: .personal, id: 0))
        let gameID = try XCTUnwrap(game.state).gameID
        let previousID = UUID()
        game.receiveAction(.submitEvidence(guestKey, attempt: 0), gameID: gameID, messageID: previousID)
        let reset = try XCTUnwrap(game.state)
        XCTAssertEqual(reset.ending, EndingState(attempt: 1))

        game.receiveAction(.submitEvidence(guestKey, attempt: 0), gameID: gameID, messageID: previousID)
        game.receiveAction(.submitEvidence(guestKey, attempt: 0), gameID: gameID, messageID: UUID())
        XCTAssertEqual(game.state, reset)

        game.confirmPerson(id: 3)
        game.receiveAction(.submitEvidence(guestKey, attempt: 1), gameID: gameID, messageID: UUID())
        XCTAssertEqual(game.phase, .ending)
        game.submitEvidence(EvidenceKey(kind: .personal, id: 0))
        XCTAssertEqual(game.phase, .cleared)
        XCTAssertEqual(try lastSnapshot().phase, .cleared)
    }

    private func connectGuest(to snapshot: GameState) {
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        XCTAssertFalse(game.isReady)
        game.receiveSnapshot(snapshot)
        XCTAssertTrue(game.isReady)
    }

    private func disconnect() {
        peer.isConnected = false
        game.connectionDidChange(connected: false)
    }

    private func reconnectGuest(to snapshot: GameState) {
        connectGuest(to: snapshot)
    }

    private func playerActions() -> [GameMessage] {
        peer.sent.filter { $0.kind == .playerAction }
    }

    private func lastSnapshot() throws -> GameState {
        let message = try XCTUnwrap(peer.sent.last)
        guard case .stateSnapshot(let snapshot) = message.payload else {
            XCTFail("Expected the last message to contain the authoritative snapshot")
            throw NSError(domain: "GameManagerTests", code: 1)
        }
        return snapshot
    }

    private func makeHostInvestigating() {
        let lobby = makeGameStateFixture()
        PlayerManager.shared.setIsHost(isHost: true)
        EpisodeManager.shared.applyGameState(lobby)
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        game.receiveAcknowledgement(gameID: lobby.gameID, revision: lobby.revision)
        game.startGame()
        game.beginInvestigation()
        XCTAssertEqual(game.phase, .investigation)
    }

    private func investigatingFixture() -> GameState {
        var snapshot = makeGameStateFixture()
        XCTAssertTrue(snapshot.start())
        XCTAssertTrue(snapshot.apply(.beginInvestigation, from: .personal))
        return snapshot
    }

    private func endingFixture() -> GameState {
        var snapshot = investigatingFixture()
        for kind in EvidenceKind.allCases {
            for evidence in snapshot.evidences(for: kind) {
                XCTAssertTrue(snapshot.apply(.collectEvidence(EvidenceKey(kind: kind, id: evidence.id)), from: kind))
            }
        }
        XCTAssertEqual(snapshot.phase, .ending)
        return snapshot
    }
}
