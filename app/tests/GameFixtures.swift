import XCTest
@testable import GameRules

func makeGameStateFixture() -> GameState {
    let episode = Episode(data: EpisodeData(
        id: 42, name: "Test episode", description: "", isActive: true,
        stories: [], personalEvidences: [0, 1], physicalEvidences: [0, 1],
        persons: [0, 3, 4], keyPersonalEvidenceID: 0, keyPhysicalEvidenceID: 1,
        keyPersonID: 3, previewResourceName: ""
    ))
    let evidences = (0...1).map { id in
        Evidence(data: EvidenceData(
            id: id, storyID: 0, resourceName: "test-model", name: "Evidence \(id)",
            description: "", classification: "Wall"
        ))
    }
    let persons = [0, 3, 4].map { id in
        Person(data: PersonData(
            id: id, name: "Person \(id)", resourceName: "",
            personalEvidenceTestimony: [:], physicalEvidenceTestimony: [:]
        ))
    }
    return GameState(episode: episode, data: GameData(
        personalEvidences: evidences, physicalEvidences: evidences,
        persons: persons, stories: [], keyPersonalEvidenceID: 0,
        keyPhysicalEvidenceID: 1, keyPersonID: 3
    ))
}

/// 台詞と調査の境界を実際の操作で通すための、2段階の小さなシナリオ。
func makeStoryGameStateFixture() -> GameState {
    var state = makeGameStateFixture()
    state.data.stories = [
        makeStoryFixture(id: 10, tag: .firstContact, statements: ["Opening one", "Opening two"]),
        makeStoryFixture(id: 11, tag: .investigation, statements: ["Investigation one"], evidenceIDs: [0]),
        makeStoryFixture(id: 12, tag: .investigation, statements: ["Investigation two"], evidenceIDs: [1])
    ]
    return state
}

func makeStoryFixture(
    id: Int,
    tag: StoryTag,
    statements: [String],
    evidenceIDs: [Int] = []
) -> Story {
    Story(data: StoryData(
        id: id, tag: tag.rawValue,
        turn: statements.enumerated().map { index, text in
            StatementData(personID: index == 0 ? 0 : 3, resourceName: "story_\(id)_\(index)", statement: text)
        },
        personalEvidences: evidenceIDs, physicalEvidences: evidenceIDs
    ))
}

/// openingから最初の調査の台詞へ続く場合も、共有状態を直接書き換えずに読む。
func finishStoryPlayback(
    in state: inout GameState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var remaining = 100
    while let playback = state.storyPlayback, remaining > 0 {
        remaining -= 1
        if !playback.isTextRevealed {
            guard state.apply(.revealStory(playbackID: playback.id), from: .personal) else {
                XCTFail("The host must be able to reveal the current statement", file: file, line: line)
                return
            }
        }
        guard state.apply(.advanceStory(playbackID: playback.id), from: .personal) else {
            XCTFail("The host must be able to advance the current statement", file: file, line: line)
            return
        }
    }
    XCTAssertNil(state.storyPlayback, "Story playback must finish", file: file, line: line)
}

func beginFixtureInvestigation(
    in state: inout GameState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(state.start(), file: file, line: line)
    if state.storyPlayback != nil {
        finishStoryPlayback(in: &state, file: file, line: line)
    } else {
        XCTAssertTrue(state.apply(.beginInvestigation, from: .personal), file: file, line: line)
        finishStoryPlayback(in: &state, file: file, line: line)
    }
    XCTAssertEqual(state.phase, .investigation, file: file, line: line)
    XCTAssertFalse(state.hasActiveStory, file: file, line: line)
}

func beginFixtureEvidencePresentation(
    in state: inout GameState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    finishStoryPlayback(in: &state, file: file, line: line)
    XCTAssertTrue(
        state.apply(.beginEvidencePresentation(attempt: state.ending.attempt), from: .personal),
        file: file, line: line
    )
}
