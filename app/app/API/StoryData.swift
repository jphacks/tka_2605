//
//  StoryData.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

struct StoryData: Codable, Hashable, Identifiable {
    var id: Int
    var tag: String
    var turn: [StatementData]
    var personalEvidences: [Int] = []
    var physicalEvidences: [Int] = []
}

extension StoryData {
    private enum CodingKeys: String, CodingKey {
        case id, tag, turn, personalEvidences, physicalEvidences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        tag = try container.decode(String.self, forKey: .tag)
        turn = try container.decode([StatementData].self, forKey: .turn)
        personalEvidences = try container.decodeIfPresent([Int].self, forKey: .personalEvidences) ?? []
        physicalEvidences = try container.decodeIfPresent([Int].self, forKey: .physicalEvidences) ?? []
    }
}

struct StatementData: Codable, Hashable {
    var personID: Int
    var resourceName: String
    var statement: String
}

class StoryDataAPI {
    private init() {}
    
    static var storyData: [StoryData] = jsonLoad("StoryData.json")
    
    static func get(id: Int) -> StoryData?{
        return storyData.filter({$0.id==id}).first
    }
}


import Playgrounds
#Playground {
    _ = StoryDataAPI.get(id: 0)!.turn
}
