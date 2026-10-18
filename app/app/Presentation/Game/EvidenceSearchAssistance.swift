import Foundation

/// Counts active exploration time without storing AR coordinates or changing
/// shared progress. A new investigation or newly acquired evidence restarts it.
struct EvidenceSearchAssistance {
    struct Scope: Equatable {
        let gameID: UUID
        let investigationIndex: Int
        let kind: EvidenceKind
    }

    private let delay: TimeInterval = 10
    private var scope: Scope?
    private var remaining: Set<EvidenceKey> = []
    private var elapsed: TimeInterval = 0
    private var lastSample: TimeInterval?

    var shouldSuggest: Bool { !remaining.isEmpty && elapsed >= delay }

    mutating func synchronize(scope: Scope?, remaining: Set<EvidenceKey>) {
        if self.scope != scope || self.remaining != remaining {
            self.scope = scope
            self.remaining = remaining
            restart()
        }
    }

    mutating func sample(at time: TimeInterval, isActive: Bool) {
        guard isActive, scope != nil, !remaining.isEmpty else {
            lastSample = nil
            return
        }
        if let lastSample { elapsed += max(0, time - lastSample) }
        lastSample = time
    }

    mutating func restart() {
        elapsed = 0
        lastSample = nil
    }
}
