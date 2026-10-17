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
