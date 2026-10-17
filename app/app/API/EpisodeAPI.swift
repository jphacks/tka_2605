//
//  EpisodeAPI.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


struct EpisodeData: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var description: String
    var stories: [Int]
    var personalEvidences: [Int]
    var physicalEvidences: [Int]
    var persons: [Int]
    var keyPersonalEvidenceID: Int
    var keyPhysicalEvidenceID: Int
    var keyPersonID: Int
    var previewResourceName: String
}

class EpisodeDataAPI {
    private init() {}
    
    static var episodeData: [EpisodeData] = jsonLoad("EpisodeData.json")

    static func get(id: Int) -> EpisodeData? {
        return episodeData.filter({$0.id == id}).first
    }
}


import Playgrounds

#Playground {
    _ = EpisodeDataAPI.get(id: 0)!.name
}
