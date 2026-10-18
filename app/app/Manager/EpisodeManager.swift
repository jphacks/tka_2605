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
    private(set) var resources: [EvidenceKey: UIImage] = [:]
    private(set) var loadError: String?

    init(episode: Episode? = nil, data: GameData? = nil) {
        self.episode = episode
        self.data = data
        self.resources = [:]
    }

    // 初期化前は送信できる状態がないためnilを返す。
    func makeGameState() -> GameState? {
        guard let episode, let data else { return nil }
        return GameState(episode: episode, data: data)
    }

    func applyGameState(_ state: GameState) {
        // 別のエピソードやゲームの画像を引き継がない。
        if episode?.id != state.episode.id || data?.id != state.data.id {
            resources.removeAll()
        }
        episode = state.episode
        data = state.data
    }

    func photo(for key: EvidenceKey) -> UIImage? {
        resources[key]
    }

    func savePhoto(_ image: UIImage, for key: EvidenceKey) {
        resources[key] = image
    }

    func clearGame() {
        episode = nil
        data = nil
        resources.removeAll()
        loadError = nil
    }

    func getAllEpisode() -> [Episode] {
        // apiより取得
        return EpisodeDataAPI.episodeData.map {
            Episode(data: $0)
        }
    }

    @discardableResult
    func initFromEpisodeID(id: Int) -> Bool {
        guard let episodeData = EpisodeDataAPI.get(id: id) else {
            loadError = "エピソード（ID: \(id)）が見つかりません。"
            return false
        }
        do {
            let resolved = try EpisodeDataResolver.resolve(
                episodeData,
                stories: StoryDataAPI.storyData,
                personalEvidences: EvidenceDataAPI.personalData,
                physicalEvidences: EvidenceDataAPI.physicalData,
                persons: PersonalDataAPI.allPersons
            )
            // 参照の検証がすべて成功してから、既存のゲーム・写真を置き換える。
            episode = Episode(data: episodeData)
            data = resolved
            resources.removeAll()
            loadError = nil
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }
}
