import Foundation

enum EpisodeDataResolutionError: LocalizedError {
    case missingReference(type: String, id: Int)

    var errorDescription: String? {
        switch self {
        case let .missingReference(type, id):
            "\(type)（ID: \(id)）が見つかりません。エピソードの参照先を確認してください。"
        }
    }
}

/// JSONの参照を検証し、Storyの順序を保ったゲームデータを組み立てる。
enum EpisodeDataResolver {
    static func resolve(
        _ episode: EpisodeData,
        stories: [StoryData],
        personalEvidences: [EvidenceData],
        physicalEvidences: [EvidenceData],
        persons: [PersonData]
    ) throws -> GameData {
        let orderedStories = try references(episode.stories, in: stories, type: "ストーリー")
        let investigations = orderedStories.filter { $0.tag == StoryTag.investigation.rawValue }
        let hasAssignments = investigations.contains { !$0.personalEvidences.isEmpty || !$0.physicalEvidences.isEmpty }
        let personalIDs = unique(hasAssignments ? investigations.flatMap(\.personalEvidences) : episode.personalEvidences ?? [])
        let physicalIDs = unique(hasAssignments ? investigations.flatMap(\.physicalEvidences) : episode.physicalEvidences ?? [])
        let personal = try references(personalIDs, in: personalEvidences, type: "人的証拠")
        let physical = try references(physicalIDs, in: physicalEvidences, type: "物的証拠")
        let orderedPersons = try references(episode.persons, in: persons, type: "人物")

        for statement in orderedStories.flatMap(\.turn) {
            guard episode.persons.contains(statement.personID) else {
                throw EpisodeDataResolutionError.missingReference(type: "台詞の登場人物", id: statement.personID)
            }
        }
        if let id = episode.keyPersonalEvidenceID, !personalIDs.contains(id) {
            throw EpisodeDataResolutionError.missingReference(type: "正解の人的証拠", id: id)
        }
        if let id = episode.keyPhysicalEvidenceID, !physicalIDs.contains(id) {
            throw EpisodeDataResolutionError.missingReference(type: "正解の物的証拠", id: id)
        }
        if let id = episode.keyPersonID, !episode.persons.contains(id) {
            throw EpisodeDataResolutionError.missingReference(type: "正解の人物", id: id)
        }

        return GameData(
            personalEvidences: personal.map(Evidence.init(data:)),
            physicalEvidences: physical.map(Evidence.init(data:)),
            persons: orderedPersons.map(Person.init(data:)),
            stories: orderedStories.map(Story.init(data:)),
            keyPersonalEvidenceID: episode.keyPersonalEvidenceID,
            keyPhysicalEvidenceID: episode.keyPhysicalEvidenceID,
            keyPersonID: episode.keyPersonID
        )
    }

    private static func references<T: Identifiable>(_ ids: [Int], in values: [T], type: String) throws -> [T] where T.ID == Int {
        try ids.map { id in
            guard let value = values.first(where: { $0.id == id }) else {
                throw EpisodeDataResolutionError.missingReference(type: type, id: id)
            }
            return value
        }
    }

    private static func unique(_ ids: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
