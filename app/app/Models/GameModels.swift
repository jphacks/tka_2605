import Foundation

enum EvidenceKind: String, Codable, Hashable, CaseIterable {
    case personal
    case physical

    var title: String { self == .personal ? "人的証拠" : "物的証拠" }
}

/// 人的証拠と物的証拠では同じ数値IDを使うため、種別も識別子に含める。
struct EvidenceKey: Codable, Hashable {
    let kind: EvidenceKind
    let id: Int
}

enum GamePhase: String, Codable, Hashable, Identifiable {
    case opening
    case investigation
    case ending
    case cleared

    var id: Self { self }
}

struct EndingState: Codable, Hashable {
    var attempt: Int = 0
    var personID: Int?
    var hostEvidenceID: Int?
    var guestEvidenceID: Int?
}

enum PlayerAction: Codable, Hashable {
    case beginInvestigation
    case collectEvidence(EvidenceKey)
    case selectPerson(id: Int, attempt: Int)
    case submitEvidence(EvidenceKey, attempt: Int)
}

/// 写真・AR座標を含まない、ホストが確定して共有する状態。
struct GameState: Codable, Hashable {
    var episode: Episode
    var data: GameData
    var phase: GamePhase?
    var revision: Int = 0
    var ending = EndingState()
    var investigationIndex: Int = 0

    var gameID: UUID { data.id }
    var totalEvidenceCount: Int { data.personalEvidences.count + data.physicalEvidences.count }
    var totalCollectedCount: Int {
        (data.personalEvidences + data.physicalEvidences).filter(\.isCollected).count
    }

    var investigationStories: [Story] {
        let stories = data.stories.filter { $0.kind == .investigation }
        // Storyに証拠指定のない旧形式は、従来どおり全証拠を1回の調査で扱う。
        return stories.contains(where: \.hasEvidenceAssignments) ? stories : []
    }

    var currentInvestigationStory: Story? {
        let stories = investigationStories
        guard stories.indices.contains(investigationIndex) else { return nil }
        return stories[investigationIndex]
    }

    var currentStory: Story? {
        switch phase {
        case .opening: data.stories.first { $0.kind == .firstContact }
        case .investigation: currentInvestigationStory
        case .ending: data.stories.first { $0.kind == .truthUncovering }
        case .cleared: data.stories.first { $0.kind == .result }
        case .none: nil
        }
    }

    func evidences(for kind: EvidenceKind) -> [Evidence] {
        kind == .personal ? data.personalEvidences : data.physicalEvidences
    }

    func evidence(for key: EvidenceKey) -> Evidence? {
        evidences(for: key.kind).first { $0.id == key.id }
    }

    func currentInvestigationEvidences(for kind: EvidenceKind) -> [Evidence] {
        guard !investigationStories.isEmpty else { return evidences(for: kind) }
        guard let story = currentInvestigationStory else { return [] }
        var seen: Set<Int> = []
        return story.evidenceIDs(for: kind).filter { seen.insert($0).inserted }.compactMap { id in
            evidence(for: EvidenceKey(kind: kind, id: id))
        }
    }

    func isEvidenceAvailableInCurrentInvestigation(_ key: EvidenceKey) -> Bool {
        currentInvestigationEvidences(for: key.kind).contains { $0.id == key.id }
    }

    @discardableResult
    mutating func start() -> Bool {
        guard phase == nil,
              !data.personalEvidences.isEmpty, !data.physicalEvidences.isEmpty,
              let personalID = data.keyPersonalEvidenceID,
              let physicalID = data.keyPhysicalEvidenceID,
              let personID = data.keyPersonID, personID != 0,
              data.personalEvidences.contains(where: { $0.id == personalID }),
              data.physicalEvidences.contains(where: { $0.id == physicalID }),
              data.persons.contains(where: { $0.id == personID }) else { return false }
        if !investigationStories.isEmpty {
            for kind in EvidenceKind.allCases {
                let assigned = Set(investigationStories.flatMap { $0.evidenceIDs(for: kind) })
                guard assigned == Set(evidences(for: kind).map(\.id)) else { return false }
            }
        }
        investigationIndex = 0
        phase = .opening
        revision += 1
        return true
    }

    /// 状態変更はホスト側でのみ呼び出す。役割・フェーズ・試行を検証する。
    @discardableResult
    mutating func apply(_ action: PlayerAction, from actor: EvidenceKind) -> Bool {
        switch action {
        case .beginInvestigation:
            guard actor == .personal, phase == .opening else { return false }
            phase = .investigation
            advanceInvestigationIfCompleted()

        case let .collectEvidence(key):
            guard phase == .investigation, key.kind == actor,
                  isEvidenceAvailableInCurrentInvestigation(key),
                  let evidence = evidence(for: key), !evidence.isCollected else { return false }
            if key.kind == .personal {
                guard let index = data.personalEvidences.firstIndex(where: { $0.id == key.id }) else { return false }
                data.personalEvidences[index].isCollected = true
            } else {
                guard let index = data.physicalEvidences.firstIndex(where: { $0.id == key.id }) else { return false }
                data.physicalEvidences[index].isCollected = true
            }
            advanceInvestigationIfCompleted()

        case let .selectPerson(id, attempt):
            guard phase == .ending, actor == .personal, attempt == ending.attempt,
                  ending.personID == nil, id != 0,
                  data.persons.contains(where: { $0.id == id }) else { return false }
            ending.personID = id

        case let .submitEvidence(key, attempt):
            guard phase == .ending, attempt == ending.attempt,
                  ending.personID != nil, key.kind == actor,
                  evidence(for: key)?.isCollected == true else { return false }
            if actor == .personal {
                guard ending.hostEvidenceID == nil else { return false }
                ending.hostEvidenceID = key.id
            } else {
                guard ending.guestEvidenceID == nil else { return false }
                ending.guestEvidenceID = key.id
            }
            if let hostID = ending.hostEvidenceID, let guestID = ending.guestEvidenceID {
                if ending.personID == data.keyPersonID,
                   hostID == data.keyPersonalEvidenceID,
                   guestID == data.keyPhysicalEvidenceID {
                    phase = .cleared
                } else {
                    ending = EndingState(attempt: ending.attempt + 1)
                }
            }
        }
        revision += 1
        return true
    }

    private mutating func advanceInvestigationIfCompleted() {
        guard !investigationStories.isEmpty else {
            if totalCollectedCount == totalEvidenceCount { phase = .ending }
            return
        }
        while let story = currentInvestigationStory {
            let completed = EvidenceKind.allCases.allSatisfy { kind in
                story.evidenceIDs(for: kind).allSatisfy { id in
                    evidence(for: EvidenceKey(kind: kind, id: id))?.isCollected == true
                }
            }
            guard completed else { return }
            if investigationIndex + 1 < investigationStories.count {
                investigationIndex += 1
            } else {
                phase = .ending
                return
            }
        }
    }
}
