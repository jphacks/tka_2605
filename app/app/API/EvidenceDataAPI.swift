//
//  EvidenceDataAPI.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


struct EvidenceData: Codable, Hashable, Identifiable {
    var id: Int
    var storyID: Int
    var resourceName: String
    var name: String
    var description: String
    var classification: String
}

class EvidenceDataAPI {
    private init() {}
    
    static var personalData: [EvidenceData] = jsonLoad("PersonalEvidenceData.json")
    static var physicalData: [EvidenceData] = jsonLoad("PhysicalEvidenceData.json")
    
    static var personalEvidenceCount: Int {
        personalData.count
    }
    static var physicalEvidenceCount: Int {
        physicalData.count
    }

    static func getPersonalEvidence(id: Int) -> EvidenceData? {
        return personalData.filter({$0.id == id}).first
    }
    
    static func getPhysicalEvidence(id: Int) -> EvidenceData? {
        return physicalData.filter({$0.id == id}).first
    }
}

import Playgrounds
#Playground {
    _ = EvidenceDataAPI.personalEvidenceCount
}
