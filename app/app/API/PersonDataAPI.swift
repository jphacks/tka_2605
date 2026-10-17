//
//  PersonalDataAPI.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


struct PersonData: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var resourceName: String
    var personalEvidenceTestimony: [Int:String]
    var physicalEvidenceTestimony: [Int:String]
}

class PersonalDataAPI {
    private init() {}
    
    static private(set) var data: [PersonData] = jsonLoad("PersonData.json")
    
    static func get(id: Int) -> PersonData? {
        return data.filter({$0.id == id}).first
    }
}

import Playgrounds
#Playground {
    _ = PersonalDataAPI.get(id: 0)!.name
}
