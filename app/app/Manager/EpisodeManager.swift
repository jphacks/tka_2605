//
//  Episode.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import ARKit


struct Episode: Codable {
    var id: Int
    var name: String
    var description: String
    var previewResourceName: String
    
    var isActive: Bool
}

struct Evidence: Codable, Hashable {
    var id: Int
    var storyID: Int
    var modelResourceName: String
    var name: String
    var description: String
    var classfication: String
    
    var isCollected: Bool = false
}

struct Person: Codable {
    var id: Int
    var tag: String
    var name: String
    var imageNamae: String
    var personalEvideceTestimony: [Int:String]
    var physicalEvideceTestimony: [Int:String]
}

struct Story: Codable {
    var id: Int
    var tag: String
    var personID: [Statement]
    
    struct Statement: Codable {
        var id: UUID = UUID()
        var personID: Int
        var resourceName: String
        var statement: String
        
        var isRead: Bool = false
    }
}

@Observable
class EpisodeManager {
    private(set) var episode: Episode? = nil
    private(set) var data: Data? = nil
    private(set) var resources: [Evidence:UIImage] = [:]
    
    init(episode: Episode? = nil, data: Data? = nil) {
        self.episode = episode
        self.data = data
        self.resources = [:]
    }
    
    func getAllEpisode() -> [Episode] {
        // apiより取得
    }
    
    func initFromEpisodeID(id: Int) {
        // apiより取得
    }
}
