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

enum EndingStage: String, Codable, Hashable {
    case personSelection
    case testimony
    case decision
    case evidenceSelection
}

struct EndingState: Codable, Hashable {
    var attempt: Int = 0
    var failedAttempts: Int = 0
    var stage: EndingStage = .personSelection
    var personID: Int?
    var hostEvidenceID: Int?
    var guestEvidenceID: Int?
}

/// 台詞ごとのIDを共有し、前の台詞に対する遅れた操作を無効にする。
struct StoryPlaybackState: Codable, Hashable, Identifiable {
    var id = UUID()
    var storyID: Int
    var turnIndex: Int = 0
    var isTextRevealed: Bool = false
}

enum PlayerAction: Codable, Hashable {
    case beginInvestigation
    case revealStory(playbackID: UUID)
    case advanceStory(playbackID: UUID)
    case advanceInvestigation(index: Int)
    case collectEvidence(EvidenceKey)
    case selectPerson(id: Int, attempt: Int)
    case beginEvidencePresentation(attempt: Int)
    case returnToPersonSelection(attempt: Int)
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
    var storyPlayback: StoryPlaybackState?

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
        if let playback = storyPlayback {
            return data.stories.first { $0.id == playback.storyID }
        }
        return switch phase {
        case .opening: data.stories.first { $0.kind == .firstContact }
        case .investigation: currentInvestigationStory
        case .ending: data.stories.first { $0.kind == .truthUncovering }
        case .cleared: data.stories.first { $0.kind == .result }
        case .none: nil
        }
    }

    var activeStatement: Story.Statement? {
        guard let playback = storyPlayback, let story = currentStory,
              story.turn.indices.contains(playback.turnIndex) else { return nil }
        return story.turn[playback.turnIndex]
    }

    var hasActiveStory: Bool { storyPlayback != nil }

    var canAdvanceInvestigation: Bool {
        guard phase == .investigation, !hasActiveStory else { return false }
        guard !investigationStories.isEmpty else {
            return totalCollectedCount == totalEvidenceCount
        }
        guard let story = currentInvestigationStory else { return false }
        return EvidenceKind.allCases.allSatisfy { kind in
            story.evidenceIDs(for: kind).allSatisfy { id in
                evidence(for: EvidenceKey(kind: kind, id: id))?.isCollected == true
            }
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
        startStory(data.stories.first { $0.kind == .firstContact })
        revision += 1
        return true
    }

    /// 状態変更はホスト側でのみ呼び出す。役割・フェーズ・試行を検証する。
    @discardableResult
    mutating func apply(_ action: PlayerAction, from actor: EvidenceKind) -> Bool {
        switch action {
        case .beginInvestigation:
            guard actor == .personal, phase == .opening, !hasActiveStory else { return false }
            beginInvestigationStory()

        case let .revealStory(playbackID):
            guard actor == .personal, var playback = storyPlayback,
                  playback.id == playbackID, activeStatement != nil,
                  !playback.isTextRevealed else { return false }
            playback.isTextRevealed = true
            storyPlayback = playback

        case let .advanceStory(playbackID):
            guard actor == .personal, let playback = storyPlayback,
                  playback.id == playbackID, let story = currentStory,
                  activeStatement != nil else { return false }
            let nextIndex: Int?
            if phase == .ending, ending.stage == .testimony {
                nextIndex = story.turn.indices.first {
                    $0 > playback.turnIndex && story.turn[$0].personID == ending.personID
                }
            } else {
                let index = playback.turnIndex + 1
                nextIndex = story.turn.indices.contains(index) ? index : nil
            }
            if let nextIndex {
                storyPlayback = StoryPlaybackState(storyID: story.id, turnIndex: nextIndex)
            } else {
                storyPlayback = nil
                if phase == .opening { beginInvestigationStory() }
                if phase == .ending, ending.stage == .testimony { ending.stage = .decision }
            }

        case let .advanceInvestigation(index):
            guard actor == .personal, index == investigationIndex,
                  canAdvanceInvestigation else { return false }
            if !investigationStories.isEmpty, index + 1 < investigationStories.count {
                investigationIndex += 1
                startStory(currentInvestigationStory)
            } else {
                phase = .ending
            }

        case let .collectEvidence(key):
            guard phase == .investigation, !hasActiveStory, key.kind == actor,
                  isEvidenceAvailableInCurrentInvestigation(key),
                  let evidence = evidence(for: key), !evidence.isCollected else { return false }
            if key.kind == .personal {
                guard let index = data.personalEvidences.firstIndex(where: { $0.id == key.id }) else { return false }
                data.personalEvidences[index].isCollected = true
            } else {
                guard let index = data.physicalEvidences.firstIndex(where: { $0.id == key.id }) else { return false }
                data.physicalEvidences[index].isCollected = true
            }

        case let .selectPerson(id, attempt):
            guard phase == .ending, !hasActiveStory, actor == .personal, attempt == ending.attempt,
                  ending.stage == .personSelection, ending.personID == nil, id != 0,
                  data.persons.contains(where: { $0.id == id }) else { return false }
            ending.personID = id
            beginTestimony(for: id)

        case let .beginEvidencePresentation(attempt):
            guard phase == .ending, !hasActiveStory, actor == .personal,
                  attempt == ending.attempt, ending.stage == .decision,
                  ending.personID != nil else { return false }
            ending.stage = .evidenceSelection

        case let .returnToPersonSelection(attempt):
            guard phase == .ending, !hasActiveStory, actor == .personal,
                  attempt == ending.attempt, ending.stage == .decision else { return false }
            ending = EndingState(attempt: ending.attempt + 1, failedAttempts: ending.failedAttempts)

        case let .submitEvidence(key, attempt):
            guard phase == .ending, !hasActiveStory, attempt == ending.attempt,
                  ending.stage == .evidenceSelection, ending.personID != nil, key.kind == actor,
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
                    startStory(data.stories.first { $0.kind == .result })
                } else {
                    ending = EndingState(
                        attempt: ending.attempt + 1,
                        failedAttempts: ending.failedAttempts + 1
                    )
                }
            }
        }
        revision += 1
        return true
    }

    private mutating func beginInvestigationStory() {
        phase = .investigation
        startStory(currentInvestigationStory)
    }

    private mutating func beginTestimony(for personID: Int) {
        guard let story = data.stories.first(where: { $0.kind == .truthUncovering }),
              let index = story.turn.firstIndex(where: { $0.personID == personID }) else {
            ending.stage = .decision
            storyPlayback = nil
            return
        }
        ending.stage = .testimony
        startStory(story, turnIndex: index)
    }

    private mutating func startStory(_ story: Story?, turnIndex: Int = 0) {
        guard let story, story.turn.indices.contains(turnIndex) else {
            storyPlayback = nil
            return
        }
        storyPlayback = StoryPlaybackState(storyID: story.id, turnIndex: turnIndex)
    }
}
