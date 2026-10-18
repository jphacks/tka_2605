import simd
import XCTest
@testable import GameRules

final class EvidenceOrientationTests: XCTestCase {
    private let worldUp = SIMD3<Float>(0, 1, 0)
    private let tolerance: Float = 0.0001

    func testWallLabelsStayUprightForEveryYawRollAndVisibleFace() {
        verifyOrientations(tilts: [.pi / 2], horizontal: false)
    }

    func testSlopedPlaneLabelsFollowProjectedWorldUpForBothFaces() {
        verifyOrientations(tilts: [.pi / 6, .pi / 3, 2 * .pi / 3, 5 * .pi / 6], horizontal: false)
    }

    func testHorizontalPlanesUseFiniteConsistentTangentOnBothFaces() {
        verifyOrientations(tilts: [0, .pi], horizontal: true)
    }

    func testHorizontalPropsStayUprightAndFacePlacementCameraRegardlessOfAnchorYaw() {
        verifyCameraHeadings(style: .upright)
    }

    func testHorizontalSheetsFaceUpAndTextTopPointsAwayFromPlacementCamera() {
        verifyCameraHeadings(style: .surfaceAligned)
    }

    func testCameraBelowTableDoesNotFlipObjectsOntoItsUnderside() {
        for tilt in [Float(0), .pi] {
            let planeRotation = simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
            let plane = simd_float4x4(planeRotation)
            for cameraHeight in [Float(-1), 1] {
                let sign = EvidencePlaneOrientation.normalSign(planeTransform: plane, cameraHeight: cameraHeight)
                let rotation = EvidencePlaneOrientation.localRotation(
                    planeTransform: plane, normalSign: sign, style: .upright, heading: SIMD2(0, 1)
                )
                let basis = simd_float3x3(planeRotation) * simd_float3x3(rotation)
                assertVector(basis.columns.1, equals: worldUp, "Camera below table")
            }
        }
    }

    func testCameraDirectlyAbovePropUsesFiniteFallbackWithoutTipping() {
        let rotation = EvidencePlaneOrientation.localRotation(
            planeTransform: matrix_identity_float4x4, normalSign: 1, style: .upright, heading: .zero
        )
        let basis = simd_float3x3(rotation)
        assertVector(basis.columns.1, equals: worldUp, "Directly above")
        XCTAssertEqual(simd_determinant(basis), 1, accuracy: tolerance)
    }

    func testSupportOffsetKeepsUprightPropAndSheetAboveRecognizedPlane() {
        let size = SIMD3<Float>(0.08, 0.20, 0.04)
        for style in [EvidencePlacementStyle.upright, .surfaceAligned] {
            let rotation = EvidencePlaneOrientation.localRotation(
                planeTransform: matrix_identity_float4x4, normalSign: 1, style: style, heading: SIMD2(1, 1)
            )
            let extent = EvidencePlaneOrientation.normalExtent(
                size: size, modelOrientation: simd_quatf(angle: 0, axis: worldUp), localRotation: rotation
            )
            var bottom = Float.infinity
            for x in [-size.x / 2, size.x / 2] {
                for y in [-size.y / 2, size.y / 2] {
                    for z in [-size.z / 2, size.z / 2] {
                        bottom = min(bottom, rotation.act(SIMD3(x, y, z)).y + extent + 0.002)
                    }
                }
            }
            XCTAssertEqual(bottom, 0.002, accuracy: tolerance)
            XCTAssertEqual(extent, style == .upright ? size.y / 2 : size.z / 2, accuracy: tolerance)
        }
    }

    private func verifyCameraHeadings(style: EvidencePlacementStyle) {
        for tilt in [Float(0), 0.08, .pi] {
            for yawIndex in 0..<12 {
                let anchor = simd_quatf(angle: Float(yawIndex) * .pi / 6, axis: worldUp)
                    * simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
                let plane = simd_float4x4(anchor)
                let planeBasis = simd_float3x3(anchor)
                let sign = EvidencePlaneOrientation.normalSign(planeTransform: plane, cameraHeight: 1)
                let normal = planeBasis.columns.1 * sign
                for cameraIndex in 0..<16 {
                    let angle = Float(cameraIndex) * .pi / 8
                    let camera = SIMD3<Float>(cos(angle), 1, sin(angle))
                    let local = planeBasis.transpose * camera
                    let heading = SIMD2(local.x, local.z)
                    let rotation = EvidencePlaneOrientation.localRotation(
                        planeTransform: plane, normalSign: sign, style: style, heading: heading
                    )
                    let basis = planeBasis * simd_float3x3(rotation)
                    let towardCamera = simd_normalize(camera - simd_dot(camera, normal) * normal)
                    assertVector(basis.columns.1, equals: style == .upright ? normal : -towardCamera,
                                 "Model up / text top")
                    assertVector(basis.columns.2, equals: style == .upright ? towardCamera : normal,
                                 "Visible front")
                    XCTAssertEqual(simd_determinant(basis), 1, accuracy: tolerance)
                }
            }
        }
    }

    private func verifyOrientations(tilts: [Float], horizontal: Bool) {
        for tilt in tilts {
            for yawIndex in 0..<12 {
                for rollIndex in 0..<8 {
                    let yaw = Float(yawIndex) * .pi / 6
                    let roll = Float(rollIndex) * .pi / 4
                    // ARKit planes use local Y as the normal. A local Y rotation
                    // changes the anchor's in-plane axes without changing its face.
                    let rotation = simd_quatf(angle: yaw, axis: worldUp)
                        * simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
                        * simd_quatf(angle: roll, axis: worldUp)
                    let planeBasis = simd_float3x3(rotation)
                    var transform = simd_float4x4(rotation)
                    transform.columns.3 = SIMD4(2.5, -1.25, 4.75, 1)
                    let normal = planeBasis.columns.1
                    let projectedUp = worldUp - simd_dot(worldUp, normal) * normal
                    let expectedUp = horizontal
                        ? simd_normalize(-planeBasis.columns.2)
                        : simd_normalize(projectedUp)
                    let context = "tilt=\(tilt), yaw=\(yaw), in-plane roll=\(roll)"
                    var bases: [simd_float3x3] = []

                    for normalSign in [Float(1), Float(-1)] {
                        let localRotation = EvidencePlaneOrientation.localRotation(
                            planeTransform: transform, normalSign: normalSign
                        )
                        XCTAssertTrue(localRotation.vector.x.isFinite, context)
                        XCTAssertTrue(localRotation.vector.y.isFinite, context)
                        XCTAssertTrue(localRotation.vector.z.isFinite, context)
                        XCTAssertTrue(localRotation.vector.w.isFinite, context)
                        let basis = planeBasis * simd_float3x3(localRotation)
                        let right = basis.columns.0
                        let up = basis.columns.1
                        let front = basis.columns.2

                        assertVector(front, equals: normal * normalSign, context)
                        assertVector(up, equals: expectedUp, context)
                        XCTAssertEqual(simd_length(right), 1, accuracy: tolerance, context)
                        XCTAssertEqual(simd_length(up), 1, accuracy: tolerance, context)
                        XCTAssertEqual(simd_length(front), 1, accuracy: tolerance, context)
                        XCTAssertEqual(simd_dot(right, up), 0, accuracy: tolerance, context)
                        XCTAssertEqual(simd_dot(up, front), 0, accuracy: tolerance, context)
                        XCTAssertEqual(simd_dot(front, right), 0, accuracy: tolerance, context)
                        assertVector(simd_cross(right, up), equals: front, context)
                        XCTAssertEqual(simd_determinant(basis), 1, accuracy: tolerance, context)
                        bases.append(basis)
                    }

                    // Changing the camera-facing side must reverse the normal and
                    // right axis while preserving the label's upright direction.
                    assertVector(bases[0].columns.1, equals: bases[1].columns.1, context)
                    assertVector(bases[0].columns.0, equals: -bases[1].columns.0, context)
                    assertVector(bases[0].columns.2, equals: -bases[1].columns.2, context)
                }
            }
        }
    }

    private func assertVector(
        _ actual: SIMD3<Float>,
        equals expected: SIMD3<Float>,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: tolerance, message, file: file, line: line)
    }
}
