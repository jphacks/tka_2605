//
//  Models.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//

import SwiftUI


struct Episode: Codable, Identifiable {
    var id: Int
    var name: String
    var description: String
    var previewResourceName: String

    var isActive: Bool
    
    init(data: EpisodeData) {
        self.id = data.id
        self.name = data.name
        self.description = data.description
        self.previewResourceName = data.previewResourceName
        self.isActive = false
    }
}

struct GameData: Codable, Identifiable {
    var id: UUID = UUID()
    var personalEvidences: [Evidence]
    var physicalEvidences: [Evidence]
    var persons: [Person]
    var stories: [Story]
    var keyPersonalEvidenceID: Int
    var keyPhysicalEvidenceID: Int
    var keyPersonID: Int

    init(data: GameData) {
        self.id = data.id
        self.personalEvidences = data.personalEvidences
        self.physicalEvidences = data.physicalEvidences
        self.persons = data.persons
        self.stories = data.stories
        self.keyPersonalEvidenceID = data.keyPersonalEvidenceID
        self.keyPhysicalEvidenceID = data.keyPhysicalEvidenceID
        self.keyPersonID = data.keyPersonID
    }
}

struct Evidence: Codable, Hashable, Identifiable {
    var id: Int
    var storyID: Int
    var modelResourceName: String
    var name: String
    var description: String
    var classification: String
    var isCollected: Bool
    
    init(data: EvidenceData) {
        self.id = data.id
        self.storyID = data.storyID
        self.modelResourceName = data.resourceName
        self.name = data.name
        self.description = data.description
        self.classification = data.classification
        
        self.isCollected = false
    }
}

struct Person: Codable, Identifiable {
    var id: Int
    var name: String
    var resourceName: String
    var personalEvidenceTestimony: [Int: String]
    var physicalEvidenceTestimony: [Int: String]
    
    init(data: PersonData) {
        self.id = data.id
        self.name = data.name
        self.resourceName = data.resourceName
        self.personalEvidenceTestimony = data.personalEvidenceTestimony
        self.physicalEvidenceTestimony = data.physicalEvidenceTestimony
    }
}

struct Story: Codable, Identifiable {
    var id: Int
    var tag: String
    var turn: [Statement]

    struct Statement: Codable {
        var id: UUID
        var personID: Int
        var resourceName: String
        var statement: String

        var isRead: Bool = false
        
        init(data: StatementData) {
            self.id = UUID()
            self.personID = data.personID
            self.resourceName = data.resourceName
            self.statement = data.statement
            self.isRead = false
        }
    }
    
    init(data: StoryData) {
        self.id = data.id
        self.tag = data.tag
        self.turn = data.turn.map({Statement(data: $0)})
    }
}
