import Foundation
import Observation

/// Replaces camera hardware only. Tests execute the production ViewModel,
/// timing policy, game managers and photo store.
@Observable @MainActor
final class EvidenceARRuntime {
    var hasCameraFeed = true
    var canCapture = false
    var isCapturing = false
    private(set) var interactionEnabled = false
    private(set) var relocationRequests: [Set<EvidenceKey>] = []

    func configure(gameID: UUID, evidences: [Evidence], kind: EvidenceKind) {}
    func setInteractionEnabled(_ enabled: Bool) { interactionEnabled = enabled }
    func setPhotographing(_ enabled: Bool) {}
    func setPhotographedEvidenceKeys(_ keys: Set<EvidenceKey>) {}
    func capturePhoto(completion: @escaping (EvidenceKey, UIImage) -> Void) {}
    func relocateUnacquiredEvidence(keys: Set<EvidenceKey>) -> Bool {
        relocationRequests.append(keys)
        return true
    }
}
