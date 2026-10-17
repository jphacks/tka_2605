//
//  Episode.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI

@Observable
class EpisodeManager {
    static let shared = EpisodeManager()
    
    private init() {}
    
    private(set) var episode: Episode? = nil
    private(set) var data: GameData? = nil
    private(set) var resources: [Evidence: UIImage] = [:]

    init(episode: Episode? = nil, data: GameData? = nil) {
        self.episode = episode
        self.data = data
        self.resources = [:]
    }

    func getAllEpisode() -> [Episode] {
        // apiより取得
        return EpisodeDataAPI.episodeData.map {
            Episode(data: $0)
        }
    }

    func initFromEpisodeID(id: Int) {
        // apiより取得
        guard let episodeData = EpisodeDataAPI.get(id: id) else { return }
        
        self.episode = Episode(data: episodeData)

        self.data = GameData.init(
            personalEvidences: episodeData.personalEvidences.map {
                Evidence(data: EvidenceDataAPI.getPersonalEvidence(id: $0)!)
            },
            physicalEvidences:episodeData.personalEvidences.map {
                Evidence(data: EvidenceDataAPI.getPhysicalEvidence(id: $0)!)
            },
            persons: episodeData.persons.map {
                Person(data: PersonalDataAPI.get(id: $0)!)
            },
            stories: episodeData.stories.map {
                Story(data: StoryDataAPI.get(id: $0)!)
            },
            keyPersonalEvidenceID: episodeData.keyPersonalEvidenceID,
            keyPhysicalEvidenceID: episodeData.keyPhysicalEvidenceID,
            keyPersonID: episodeData.keyPersonID
        )
    }
}
