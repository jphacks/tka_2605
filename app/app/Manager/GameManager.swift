import SwiftUI

/// 共有状態の変更はホストだけが確定する。写真・AR配置は各端末に残す。
@Observable
final class GameManager {
    static let shared = GameManager()

    private(set) var state: GameState?
    private(set) var lastError: String?
    private(set) var isSynchronized = false
    @ObservationIgnored private var processedMessages: Set<UUID> = []
    @ObservationIgnored private var pendingCollections: [EvidenceKey: UUID] = [:]
    private var pendingSubmission: (key: EvidenceKey, attempt: Int, id: UUID)?

    private init() {}

    var phase: GamePhase? { state?.phase }
    var isHost: Bool { PlayerManager.shared.selfPlayer.isHost }
    var myKind: EvidenceKind { isHost ? .personal : .physical }
    var isReady: Bool { PeerManager.shared.isConnected && isSynchronized }
    var connectionMessage: String? {
        guard !isReady else { return nil }
        return PeerManager.shared.isConnected
            ? "ゲームの状態を同期しています"
            : "接続が切れました。同じ相手との再接続を待っています"
    }
    var myEvidences: [Evidence] { state?.evidences(for: myKind) ?? [] }
    var myCollectedCount: Int { myEvidences.filter(\.isCollected).count }
    var myTotalCount: Int { myEvidences.count }
    var totalCollectedCount: Int { state?.totalCollectedCount ?? 0 }
    var totalEvidenceCount: Int { state?.totalEvidenceCount ?? 0 }
    var myPendingEvidenceID: Int? { pendingSubmission?.key.id }

    func startGame() {
        guard isHost, isReady, var snapshot = hostSnapshot() else { return }
        guard snapshot.start() else {
            lastError = "このエピソードの証拠・正解データを確認してください"
            return
        }
        lastError = nil
        accept(snapshot)
        broadcast()
    }

    func beginInvestigation() {
        performHostAction(.beginInvestigation)
    }

    func confirmPerson(id: Int) {
        guard let state else { return }
        performHostAction(.selectPerson(id: id, attempt: state.ending.attempt))
    }

    func submitEvidence(_ key: EvidenceKey) {
        guard isReady, let state, state.phase == .ending,
              key.kind == myKind, state.evidence(for: key)?.isCollected == true,
              state.ending.personID != nil else { return }
        let action = PlayerAction.submitEvidence(key, attempt: state.ending.attempt)
        if isHost {
            performHostAction(action)
        } else {
            guard state.ending.guestEvidenceID == nil, pendingSubmission == nil else { return }
            let messageID = UUID()
            pendingSubmission = (key, state.ending.attempt, messageID)
            PeerManager.shared.sendPayload(.playerAction(gameID: state.gameID, action: action), messageID: messageID)
        }
    }

    func recordPhoto(_ image: UIImage, for key: EvidenceKey) {
        guard isReady, let state, state.phase == .investigation,
              key.kind == myKind, state.evidence(for: key) != nil else { return }
        EpisodeManager.shared.savePhoto(image, for: key)
        lastError = nil
        guard state.evidence(for: key)?.isCollected != true else { return }
        if isHost {
            performHostAction(.collectEvidence(key))
        } else {
            let id = pendingCollections[key] ?? UUID()
            pendingCollections[key] = id
            PeerManager.shared.sendPayload(.playerAction(gameID: state.gameID, action: .collectEvidence(key)), messageID: id)
        }
    }

    func connectionDidChange(connected: Bool) {
        isSynchronized = false
        guard connected else { return }
        if isHost, let snapshot = hostSnapshot() {
            PeerManager.shared.sendPayload(.stateSnapshot(state: snapshot))
        }
    }

    func receiveSnapshot(_ snapshot: GameState) {
        guard !isHost, PeerManager.shared.isConnected else { return }
        if let current = state {
            if current.phase != nil && current.gameID != snapshot.gameID { return }
            if current.gameID == snapshot.gameID && snapshot.revision < current.revision {
                PeerManager.shared.sendPayload(.snapshotAcknowledgement(gameID: current.gameID, revision: current.revision))
                return
            }
        }
        let needsReplay = !isSynchronized
        if state?.gameID != snapshot.gameID {
            pendingCollections.removeAll()
            pendingSubmission = nil
        }
        accept(snapshot)
        reconcilePending(with: snapshot)
        PeerManager.shared.sendPayload(.snapshotAcknowledgement(gameID: snapshot.gameID, revision: snapshot.revision))
        isSynchronized = true
        if needsReplay { replayPending(in: snapshot) }
    }

    func receiveAcknowledgement(gameID: UUID, revision: Int) {
        guard isHost, PeerManager.shared.isConnected,
              let state, state.gameID == gameID, state.revision == revision else { return }
        isSynchronized = true
    }

    func receiveAction(_ action: PlayerAction, gameID: UUID, messageID: UUID) {
        guard isHost, isReady, var snapshot = state, snapshot.gameID == gameID else { return }
        if !processedMessages.contains(messageID) {
            processedMessages.insert(messageID)
            if snapshot.apply(action, from: .physical) { accept(snapshot) }
        }
        // 再送・拒否でも確定状態を返し、参加者側が未確認操作を照合できるようにする。
        broadcast()
    }

    private func performHostAction(_ action: PlayerAction) {
        guard isHost, isReady, var snapshot = state else { return }
        guard snapshot.apply(action, from: .personal) else { return }
        lastError = nil
        accept(snapshot)
        broadcast()
    }

    private func hostSnapshot() -> GameState? {
        guard let loaded = EpisodeManager.shared.makeGameState() else { return nil }
        if state?.gameID != loaded.gameID {
            state = loaded
            processedMessages.removeAll()
            pendingCollections.removeAll()
            pendingSubmission = nil
        }
        return state
    }

    private func accept(_ snapshot: GameState) {
        state = snapshot
        EpisodeManager.shared.applyGameState(snapshot)
        if snapshot.phase != nil { ScreenManager.shared.setScreenState(.Game) }
    }

    private func broadcast() {
        guard let state else { return }
        PeerManager.shared.sendPayload(.stateSnapshot(state: state))
    }

    private func reconcilePending(with snapshot: GameState) {
        pendingCollections = pendingCollections.filter { key, _ in
            snapshot.phase == .investigation && snapshot.evidence(for: key)?.isCollected == false
        }
        if let submission = pendingSubmission,
           snapshot.phase != .ending || submission.attempt != snapshot.ending.attempt || snapshot.ending.guestEvidenceID != nil {
            pendingSubmission = nil
        }
    }

    private func replayPending(in snapshot: GameState) {
        for (key, id) in pendingCollections {
            PeerManager.shared.sendPayload(.playerAction(gameID: snapshot.gameID, action: .collectEvidence(key)), messageID: id)
        }
        if let submission = pendingSubmission {
            PeerManager.shared.sendPayload(
                .playerAction(gameID: snapshot.gameID, action: .submitEvidence(submission.key, attempt: submission.attempt)),
                messageID: submission.id
            )
        }
    }

    func returnToTitle() {
        PeerManager.shared.disconnect()
        state = nil
        isSynchronized = false
        lastError = nil
        pendingCollections.removeAll()
        pendingSubmission = nil
        processedMessages.removeAll()
        EpisodeManager.shared.clearGame()
        ScreenManager.shared.titleStatePath = [.Title]
        ScreenManager.shared.setScreenState(.Title)
    }
}
