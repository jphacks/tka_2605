import Foundation
import XCTest
@testable import GameRules

final class EvidenceSearchAssistanceTests: XCTestCase {
    private let key = EvidenceKey(kind: .physical, id: 1)

    func testTenSecondBoundaryAndResetAfterReposition() {
        var policy = makePolicy()
        policy.sample(at: 0, isActive: true)
        policy.sample(at: 9.999, isActive: true)
        XCTAssertFalse(policy.shouldSuggest)
        policy.sample(at: 10, isActive: true)
        XCTAssertTrue(policy.shouldSuggest)
        policy.restart()
        policy.sample(at: 10, isActive: true)
        policy.sample(at: 19.999, isActive: true)
        XCTAssertFalse(policy.shouldSuggest)
        policy.sample(at: 20, isActive: true)
        XCTAssertTrue(policy.shouldSuggest)
    }

    func testPausedTimeIsExcluded() {
        var policy = makePolicy()
        policy.sample(at: 0, isActive: true)
        policy.sample(at: 4, isActive: true)
        policy.sample(at: 4, isActive: false)
        policy.sample(at: 1000, isActive: false)
        policy.sample(at: 1000, isActive: true)
        policy.sample(at: 1005.999, isActive: true)
        XCTAssertFalse(policy.shouldSuggest)
        policy.sample(at: 1006, isActive: true)
        XCTAssertTrue(policy.shouldSuggest)
    }

    func testAcquisitionAndNewInvestigationResetCountdown() {
        var policy = EvidenceSearchAssistance()
        let scope = EvidenceSearchAssistance.Scope(gameID: UUID(), investigationIndex: 0, kind: .physical)
        let other = EvidenceKey(kind: .physical, id: 2)
        policy.synchronize(scope: scope, remaining: [key, other])
        policy.sample(at: 0, isActive: true)
        policy.sample(at: 10, isActive: true)
        XCTAssertTrue(policy.shouldSuggest)
        policy.synchronize(scope: scope, remaining: [other])
        XCTAssertFalse(policy.shouldSuggest)
        policy.sample(at: 10, isActive: true)
        policy.sample(at: 20, isActive: true)
        XCTAssertTrue(policy.shouldSuggest)
        policy.synchronize(scope: .init(gameID: scope.gameID, investigationIndex: 1, kind: .physical), remaining: [other])
        XCTAssertFalse(policy.shouldSuggest)
    }

    func testWaitingForPartnerWithNoRemainingEvidenceNeverSuggestsRelocation() {
        var policy = makePolicy()
        policy.synchronize(scope: nil, remaining: [])
        policy.sample(at: 0, isActive: true)
        policy.sample(at: 100, isActive: true)
        XCTAssertFalse(policy.shouldSuggest)
    }

    private func makePolicy() -> EvidenceSearchAssistance {
        var policy = EvidenceSearchAssistance()
        policy.synchronize(scope: .init(gameID: UUID(), investigationIndex: 0, kind: .physical), remaining: [key])
        return policy
    }
}
