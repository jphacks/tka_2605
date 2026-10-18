import AppKit
import Foundation
import XCTest
@testable import GameRules

final class EpisodeDataTests: XCTestCase {
    func testUpdatedJSONDecodesMissingEpisodeEvidenceListsAndOptionalStoryLists() throws {
        let catalog = try catalog()
        XCTAssertNil(catalog.episode.personalEvidences)
        XCTAssertNil(catalog.episode.physicalEvidences)
        XCTAssertEqual(catalog.stories.count, 6)
        XCTAssertEqual(catalog.stories[0].personalEvidences, [])
        XCTAssertEqual(catalog.stories[0].physicalEvidences, [])
        XCTAssertEqual(catalog.stories[1].personalEvidences, [1, 5])
        XCTAssertEqual(catalog.stories[1].physicalEvidences, [2, 5])
        let decoded = try JSONDecoder().decode([StoryData].self, from: JSONEncoder().encode(catalog.stories))
        XCTAssertEqual(decoded, catalog.stories)
        let people = try decode([PersonData].self, from: "PersonData")
        XCTAssertFalse(try XCTUnwrap(people.first { $0.id == 3 }?.personalEvidenceTestimony[0]).isEmpty)
    }

    func testResolverCollectsUniqueEvidenceInStoryOrderAndPreservesAllStories() throws {
        let catalog = try catalog()
        var stories = catalog.stories
        stories[1].personalEvidences.append(1)
        stories[2].personalEvidences.append(1)
        let data = try catalog.resolve(stories: stories)
        XCTAssertEqual(data.personalEvidences.map(\.id), [1, 5, 3, 4, 0, 2])
        XCTAssertEqual(data.physicalEvidences.map(\.id), [2, 5, 0, 4, 1, 3])
        XCTAssertEqual(data.stories.map(\.id), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(data.personalEvidences.first { $0.id == 0 }?.classification, "Floor")
        XCTAssertEqual(data.stories[2].personalEvidenceIDs, [3, 4, 1])
        let state = GameState(episode: Episode(data: catalog.episode), data: data)
        XCTAssertEqual(state.currentInvestigationEvidences(for: .personal).map(\.id), [1, 5])
    }

    func testResolverRejectsMissingStoryEvidencePersonAndAnswerReferences() throws {
        let catalog = try catalog()
        var episode = catalog.episode
        episode.stories.append(999)
        XCTAssertThrowsError(try catalog.resolve(episode: episode))

        let missingEvidence = catalog.personal.filter { $0.id != 5 }
        XCTAssertThrowsError(try catalog.resolve(personal: missingEvidence))

        var stories = catalog.stories
        stories[0].turn[0].personID = 999
        XCTAssertThrowsError(try catalog.resolve(stories: stories))

        episode = catalog.episode
        episode.keyPhysicalEvidenceID = 999
        XCTAssertThrowsError(try catalog.resolve(episode: episode))
    }

    func testBothPlayersMustCompleteEachStoryAndOnlyFinalStoryEntersEnding() throws {
        var state = try state()
        XCTAssertTrue(state.start())
        XCTAssertEqual(state.currentStory?.id, 0)
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal))
        XCTAssertEqual(state.investigationStories.count, 3)
        XCTAssertEqual(state.currentStory?.id, 1)
        XCTAssertEqual(state.currentInvestigationEvidences(for: .personal).map(\.id), [1, 5])
        XCTAssertEqual(state.currentInvestigationEvidences(for: .physical).map(\.id), [2, 5])

        let unchanged = state
        XCTAssertFalse(state.apply(.collectEvidence(key(.personal, 0)), from: .personal))
        XCTAssertEqual(state, unchanged, "Future-stage evidence cannot be collected early")
        for id in [1, 5] { XCTAssertTrue(state.apply(.collectEvidence(key(.personal, id)), from: .personal)) }
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 2)), from: .physical))
        XCTAssertEqual(state.currentStory?.id, 1, "One player's completion must not advance the stage")
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 5)), from: .physical))
        XCTAssertEqual(state.currentStory?.id, 2)
        XCTAssertEqual(state.investigationIndex, 1)
        XCTAssertEqual(state.totalCollectedCount, 4)
        XCTAssertEqual(state.phase, .investigation)

        try collectCurrentStory(in: &state)
        XCTAssertEqual(state.currentStory?.id, 3)
        XCTAssertEqual(state.totalCollectedCount, 8)
        XCTAssertEqual(state.phase, .investigation)
        try collectCurrentStory(in: &state)
        XCTAssertEqual(state.phase, .ending)
        XCTAssertEqual(state.currentStory?.id, 4)
        XCTAssertEqual(state.totalCollectedCount, 12)

        XCTAssertTrue(state.apply(.selectPerson(id: 3, attempt: 0), from: .personal))
        XCTAssertTrue(state.apply(.submitEvidence(key(.personal, 0), attempt: 0), from: .personal))
        XCTAssertTrue(state.apply(.submitEvidence(key(.physical, 0), attempt: 0), from: .physical))
        XCTAssertEqual(state.phase, .cleared)
        XCTAssertEqual(state.currentStory?.id, 5)
    }

    func testIntermediateStageAndCollectedEvidenceSurviveSnapshotRoundTrip() throws {
        var original = try investigatingState()
        try collectCurrentStory(in: &original)
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.currentStory?.id, 2)
        XCTAssertEqual(decoded.evidence(for: key(.personal, 1))?.isCollected, true)
        XCTAssertEqual(decoded.currentInvestigationEvidences(for: .physical).map(\.id), [0, 4])
    }

    func testStartRejectsEvidenceThatIsNotAssignedToAnyInvestigation() throws {
        var state = try state()
        state.data.stories[1].personalEvidenceIDs.removeAll { $0 == 1 }
        XCTAssertFalse(state.start())
    }

    func testLegacyEpisodeEvidenceListsRemainUsableWithoutStoryAssignments() throws {
        let catalog = try catalog()
        var episode = catalog.episode
        episode.stories = []
        episode.personalEvidences = [0, 1]
        episode.physicalEvidences = [0, 1]
        var state = GameState(episode: Episode(data: episode), data: try catalog.resolve(episode: episode))
        XCTAssertTrue(state.start())
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal))
        XCTAssertTrue(state.investigationStories.isEmpty)
        XCTAssertEqual(state.currentInvestigationEvidences(for: .personal).map(\.id), [0, 1])
        for kind in EvidenceKind.allCases {
            for id in [0, 1] { XCTAssertTrue(state.apply(.collectEvidence(key(kind, id)), from: kind)) }
        }
        XCTAssertEqual(state.phase, .ending)
    }

    func testReconnectingAfterStageAdvanceKeepsPhotosAndDoesNotReplayConfirmedOldStage() throws {
        let game = GameManager.shared
        let peer = PeerManager.shared
        game.returnToTitle()
        PlayerManager.shared.setIsHost(isHost: false)
        defer { game.returnToTitle(); peer.clearSent() }
        var state = try investigatingState()
        for id in [1, 5] { XCTAssertTrue(state.apply(.collectEvidence(key(.personal, id)), from: .personal)) }
        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 2)), from: .physical))
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        game.receiveSnapshot(state)
        let photo = NSImage()
        game.recordPhoto(photo, for: key(.physical, 5))
        peer.isConnected = false
        game.connectionDidChange(connected: false)

        XCTAssertTrue(state.apply(.collectEvidence(key(.physical, 5)), from: .physical))
        peer.clearSent()
        peer.isConnected = true
        game.connectionDidChange(connected: true)
        game.receiveSnapshot(state)
        XCTAssertTrue(game.isReady)
        XCTAssertEqual(game.currentStory?.id, 2)
        XCTAssertEqual(game.currentInvestigationEvidences.map(\.id), [0, 4])
        XCTAssertEqual(game.myCollectedCount, 2)
        XCTAssertEqual(game.myTotalCount, 6)
        XCTAssertTrue(EpisodeManager.shared.photo(for: key(.physical, 5)) === photo)
        XCTAssertFalse(peer.sent.contains { $0.kind == .playerAction })
        game.recordPhoto(NSImage(), for: key(.physical, 1))
        XCTAssertNil(EpisodeManager.shared.photo(for: key(.physical, 1)), "A future-stage photograph must not be accepted")
    }

    private func collectCurrentStory(in state: inout GameState) throws {
        let story = try XCTUnwrap(state.currentInvestigationStory)
        for kind in EvidenceKind.allCases {
            for id in story.evidenceIDs(for: kind) {
                XCTAssertTrue(state.apply(.collectEvidence(key(kind, id)), from: kind))
            }
        }
    }

    private func state() throws -> GameState {
        let catalog = try catalog()
        return GameState(episode: Episode(data: catalog.episode), data: try catalog.resolve())
    }

    private func investigatingState() throws -> GameState {
        var state = try state()
        XCTAssertTrue(state.start())
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal))
        return state
    }

    private func key(_ kind: EvidenceKind, _ id: Int) -> EvidenceKey { EvidenceKey(kind: kind, id: id) }

    private func decode<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: filename, withExtension: "json", subdirectory: "Resources"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func catalog() throws -> Catalog {
        Catalog(
            episode: try XCTUnwrap(decode([EpisodeData].self, from: "EpisodeData").first { $0.id == 0 }),
            stories: try decode([StoryData].self, from: "StoryData"),
            personal: try decode([EvidenceData].self, from: "PersonalEvidenceData"),
            physical: try decode([EvidenceData].self, from: "PhysicalEvidenceData"),
            persons: try decode([PersonData].self, from: "PersonData")
        )
    }

    private struct Catalog {
        let episode: EpisodeData
        let stories: [StoryData]
        let personal: [EvidenceData]
        let physical: [EvidenceData]
        let persons: [PersonData]

        func resolve(episode: EpisodeData? = nil, stories: [StoryData]? = nil, personal: [EvidenceData]? = nil) throws -> GameData {
            try EpisodeDataResolver.resolve(
                episode ?? self.episode, stories: stories ?? self.stories,
                personalEvidences: personal ?? self.personal,
                physicalEvidences: physical, persons: persons
            )
        }
    }
}
