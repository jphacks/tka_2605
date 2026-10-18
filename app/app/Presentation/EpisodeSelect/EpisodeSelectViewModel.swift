//
//  EpisodeSelectViewModel.swift
//  app
//
//  Created by tknooa on 2026/10/17.
//


import SwiftUI


@Observable
class EpisodeSelectViewModel {
    private var episode = EpisodeManager.shared
    private var screen = ScreenManager.shared
    private var peer = PeerManager.shared
    
    private(set) var selectedEpisode: Episode?
    private var episodeToPlayAfterDismissal: Episode?
    
    func getEpisodes() -> [Episode] {
        return episode.getAllEpisode()
    }
    
    func onClickEpisodeButton(episodeID: Int) {
        guard let selected = getEpisodes().first(where: { $0.id == episodeID }),
              selected.isActive else { return }
        episodeToPlayAfterDismissal = nil
        selectedEpisode = selected
    }

    func cancelEpisodeSelection() {
        // SwiftUIが閉じた後に再度nilを書き戻しても、確定済みの選択は取り消さない。
        guard selectedEpisode != nil else { return }
        episodeToPlayAfterDismissal = nil
        selectedEpisode = nil
    }

    func confirmEpisodeSelection() {
        guard let selectedEpisode else { return }
        episodeToPlayAfterDismissal = selectedEpisode
        self.selectedEpisode = nil
    }

    func confirmationDidDismiss() {
        guard let selected = episodeToPlayAfterDismissal else { return }
        episodeToPlayAfterDismissal = nil
        episode.initFromEpisodeID(id: selected.id)
        screen.titleStatePath.append(.Robbie)
    }
    
    func connectClose() {
        self.peer.disconnect()
    }
}
