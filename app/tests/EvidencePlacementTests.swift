import Foundation
import RealityKit
import XCTest
@testable import GameRules

final class EvidencePlacementTests: XCTestCase {
    private let bookKey = EvidenceKey(kind: .physical, id: 2)
    private let footprintKey = EvidenceKey(kind: .physical, id: 5)
    @MainActor private static var registered = false

    @MainActor
    func testInitiallyHiddenModelsRecoverAfterFailedPlacementWithoutNewSurfaceRevision() {
        let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
        var input = makeInput()
        var output = EvidenceAROutputComponent()
        update(&input, &output, [book], [], 0)
        XCTAssertEqual(output.placedCount, 0)
        XCTAssertEqual(output.placementFeedback.first?.reason, .surface)
        XCTAssertFalse(book.findEntity(named: EvidenceEntityNames.visual)!.isEnabled)
        let revision = input.processedSurfaceRevision
        update(&input, &output, [book], [rectangle(.table, width: 0.8, length: 0.8, height: 0.75)], 1)
        XCTAssertEqual(input.processedSurfaceRevision, revision)
        XCTAssertEqual(output.placedCount, 1)
        XCTAssertTrue(book.findEntity(named: EvidenceEntityNames.visual)!.isEnabled)
    }

    @MainActor
    func testActualCandidateHeadingFindsNarrowTableRejectedByCenterHeading() {
        let table = rectangle(.table, width: 0.12, length: 0.3, height: 0.75)
        var model = EvidenceModelConfiguration()
        model.size = SIMD3(0.145, 0.2, 0.093)
        model.placementStyle = .upright
        let camera = SIMD2<Float>(0, 0.01)
        // Facing the camera projection from the table center is too wide.
        XCTAssertFalse(EvidenceARGeometry.fits(model, at: .zero, sign: 1, in: table, heading: camera))
        let candidates = EvidenceARGeometry.candidates(in: table, model: model, sign: 1, near: camera)
        XCTAssertFalse(candidates.isEmpty)
        for point in candidates {
            XCTAssertTrue(EvidenceARGeometry.fits(model, at: point, sign: 1, in: table, heading: camera - point))
        }
    }

    @MainActor
    func testLateTableRecognitionCanMoveUnacquiredFootprintsToFitBothModels() {
        let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
        let footprints = makeEvidence(key: footprintKey, size: SIMD3(0.61, 3.333333, 0.011), surface: .floor)
        let floor = rectangle(.floor, width: 2, length: 5)
        let table = rectangle(.table, width: 0.44, length: 0.6, height: 0.75)
        var input = makeInput()
        var output = EvidenceAROutputComponent()
        update(&input, &output, [book, footprints], [floor], 0)
        XCTAssertEqual(output.placedCount, 1)
        let initialFootprints = footprints.position(relativeTo: nil)
        // Every table point is within 1m of the initial central footprint pose.
        XCTAssertLessThan(simd_length(initialFootprints), 0.02)
        input.surfaceRevision += 1
        update(&input, &output, [book, footprints], [floor, table], 0.4)
        XCTAssertEqual(output.placedCount, 2)
        XCTAssertGreaterThanOrEqual(simd_distance(book.position(relativeTo: nil), footprints.position(relativeTo: nil)), 1)
        XCTAssertGreaterThan(simd_distance(initialFootprints, footprints.position(relativeTo: nil)), 0.1)
        XCTAssertTrue(output.placementFeedback.isEmpty)
    }

    @MainActor
    func testCollectedAndPhotographedModelsNeverMoveToMakeRoomForOtherEvidence() {
        for isCollected in [true, false] {
            let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
            let footprints = makeEvidence(key: footprintKey, size: SIMD3(0.61, 3.333333, 0.011), surface: .floor)
            let floor = rectangle(.floor, width: 2, length: 5)
            let table = rectangle(.table, width: 0.44, length: 0.6, height: 0.75)
            var input = makeInput()
            var output = EvidenceAROutputComponent()
            update(&input, &output, [book, footprints], [floor], 0)
            let original = footprints.transformMatrix(relativeTo: nil)
            var evidence = footprints.components[EvidenceComponent.self]!
            evidence.isCollected = isCollected
            evidence.isPhotographed = !isCollected
            footprints.components.set(evidence)
            input.relocationKeys = [bookKey, footprintKey]
            update(&input, &output, [book, footprints], [floor, table], 1)
            XCTAssertEqual(footprints.transformMatrix(relativeTo: nil), original)
            XCTAssertEqual(output.placedCount, 1)
            XCTAssertEqual(output.placementFeedback.first?.reason, .spacing)
        }
    }

    @MainActor
    func testNoFallbackToFloorWhenTableClassificationIsMissing() {
        let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
        var input = makeInput()
        var output = EvidenceAROutputComponent()
        for _ in 0..<3 {
            input.relocationKeys = [bookKey]
            update(&input, &output, [book], [rectangle(.floor, width: 3, length: 3)], 1)
            XCTAssertEqual(output.placedCount, 0)
            XCTAssertEqual(output.placementFeedback.first?.reason, .surface)
        }
    }

    @MainActor
    func testInsufficientAreaIsReportedAndRecoversWhenAreaBecomesUsable() {
        let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
        var input = makeInput()
        var output = EvidenceAROutputComponent()
        update(&input, &output, [book], [rectangle(.table, width: 0.02, length: 0.02, height: 0.75)], 0)
        XCTAssertEqual(output.placementFeedback.first?.reason, .area)
        update(&input, &output, [book], [rectangle(.table, width: 0.8, length: 0.8, height: 0.75)], 1)
        XCTAssertEqual(output.placedCount, 1)
    }

    @MainActor
    func testRepeatedRelocationAndTrackingRecoveryDoNotStrandHiddenEntity() {
        let book = makeEvidence(key: bookKey, size: SIMD3(0.145, 0.2, 0.093), surface: .table, style: .upright)
        var input = makeInput()
        var output = EvidenceAROutputComponent()
        input.trackingNormal = false
        input.relocationKeys = [bookKey]
        let table = rectangle(.table, width: 0.8, length: 0.8, height: 0.75)
        update(&input, &output, [book], [table], 1)
        XCTAssertEqual(output.placedCount, 0)
        input.trackingNormal = true
        update(&input, &output, [book], [table], 1)
        XCTAssertEqual(output.placedCount, 1)
        for _ in 0..<3 {
            input.relocationKeys = [bookKey]
            update(&input, &output, [book], [table], 0.1)
            XCTAssertEqual(output.placedCount, 1)
            XCTAssertTrue(book.findEntity(named: EvidenceEntityNames.visual)!.isEnabled)
        }
    }

    @MainActor
    private func makeEvidence(key: EvidenceKey, size: SIMD3<Float>, surface: EvidenceSurfaceClassification,
                              style: EvidencePlacementStyle = .surfaceAligned) -> Entity {
        if !Self.registered {
            EvidenceComponent.registerComponent()
            EvidencePlacementComponent.registerComponent()
            Self.registered = true
        }
        var model = EvidenceModelConfiguration()
        model.size = size
        model.placementStyle = style
        model.captureMesh = .box(size: size)
        let entity = Entity()
        entity.components.set(EvidenceComponent(key: key, name: "Evidence \(key.id)", requiredSurface: surface,
                                                model: model, isCollected: false))
        entity.components.set(EvidencePlacementComponent())
        let visual = Entity()
        visual.name = EvidenceEntityNames.visual
        visual.isEnabled = false
        entity.addChild(visual)
        return entity
    }

    private func makeInput() -> EvidenceARInputComponent {
        var input = EvidenceARInputComponent()
        input.interactionEnabled = true
        input.trackingNormal = true
        input.cameraTransform.columns.3 = SIMD4(0, 1.4, 0, 1)
        return input
    }

    private func rectangle(_ classification: EvidenceSurfaceClassification, width: Float, length: Float,
                           height: Float = 0) -> RecognizedSurfaceComponent {
        var transform = matrix_identity_float4x4
        transform.columns.3.y = height
        return RecognizedSurfaceComponent(anchorID: UUID(), classification: classification, transform: transform,
            boundary: [SIMD2(-width/2, -length/2), SIMD2(width/2, -length/2),
                       SIMD2(width/2, length/2), SIMD2(-width/2, length/2)])
    }

    @MainActor
    private func update(_ input: inout EvidenceARInputComponent, _ output: inout EvidenceAROutputComponent,
                        _ entities: [Entity], _ surfaces: [RecognizedSurfaceComponent], _ delta: TimeInterval) {
        EvidencePlacementEngine.update(input: &input, output: &output, evidences: entities,
                                       surfaces: surfaces, deltaTime: delta)
    }
}
