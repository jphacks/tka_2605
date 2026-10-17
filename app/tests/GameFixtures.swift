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
