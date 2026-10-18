import Foundation
import RealityKit
#if canImport(ARKit)
import ARKit
#endif

/// AR coordinates and the photos stay on this device. Only EvidenceKey crosses the network.
nonisolated struct EvidenceComponent: Component {
    let key: EvidenceKey
    let name: String
    let requiredSurface: EvidenceSurfaceClassification?
    let model: EvidenceModelConfiguration
    var isCollected: Bool
    var isPhotographed = false
}

/// Bounds control placement; the rendered mesh controls picking and surface distance.
nonisolated struct EvidenceModelConfiguration {
    var size: SIMD3<Float> = SIMD3(0.10, 0.10, 0.006)
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
    var captureMesh = EvidenceCaptureMesh.box(size: SIMD3(0.10, 0.10, 0.006))
    var placementStyle: EvidencePlacementStyle = .surfaceAligned
}

nonisolated enum EvidenceSurfaceClassification: String {
    case wall, floor, ceiling, table, seat, window, door

    var displayName: String {
        switch self {
        case .wall: "壁"
        case .floor: "床"
        case .ceiling: "天井"
        case .table: "机の天板"
        case .seat: "座面"
        case .window: "窓"
        case .door: "ドア"
        }
    }

    init?(dataValue: String) {
        self.init(rawValue: dataValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    #if canImport(ARKit)
    init?(_ classification: ARPlaneAnchor.Classification) {
        switch classification {
        case .wall: self = .wall
        case .floor: self = .floor
        case .ceiling: self = .ceiling
        case .table: self = .table
        case .seat: self = .seat
        case .window: self = .window
        case .door: self = .door
        default: return nil
        }
    }
    #endif
}

nonisolated struct RecognizedSurfaceComponent: Component {
    let anchorID: UUID
    let classification: EvidenceSurfaceClassification?
    let transform: simd_float4x4
    let boundary: [SIMD2<Float>]
}

nonisolated struct EvidencePlacementComponent: Component {
    var anchorID: UUID?
    var planePosition: SIMD2<Float> = .zero
    var normalSign: Float = 1
    var surfaceHeading: SIMD2<Float>?
    var isValid = false
    var prefersNearbySurface = false
    var waitingReason: EvidencePlacementWaitingReason?
}

nonisolated enum EvidencePlacementWaitingReason: Equatable {
    case surface, area, spacing
}

nonisolated struct EvidencePlacementFeedback: Equatable {
    let key: EvidenceKey
    let name: String
    let surface: EvidenceSurfaceClassification?
    let reason: EvidencePlacementWaitingReason

    var message: String {
        let location = surface?.displayName ?? "配置面"
        switch reason {
        case .surface: return "\(name)：\(location)をゆっくり映して認識させてください"
        case .area: return "\(name)：モデル全体が収まる\(location)の範囲を探しています"
        case .spacing: return "\(name)：他の証拠から1m離れた場所を探しています"
        }
    }
}

nonisolated struct EvidenceCaptureRequest {
    let id: UUID
    let key: EvidenceKey
}

nonisolated enum EvidenceCaptureDecision {
    case approved(EvidenceCaptureRequest)
    case rejected(UUID)
}

nonisolated struct EvidenceARInputComponent: Component {
    var interactionEnabled = false
    var photographing = false
    var trackingNormal = false
    var cameraTransform = matrix_identity_float4x4
    var viewProjection = matrix_identity_float4x4
    var viewportSize = CGSize.zero
    var tapRay: (origin: SIMD3<Float>, direction: SIMD3<Float>)?
    var captureRequest: EvidenceCaptureRequest?
    var relocationKeys: Set<EvidenceKey> = []
    var surfaceRevision = 0
    var processedSurfaceRevision = -1
    var placementElapsed: TimeInterval = 1
}

nonisolated struct EvidenceAROutputComponent: Component {
    var selectedKey: EvidenceKey?
    var selectedName: String?
    var canCapture = false
    var placedCount = 0
    var captureDecision: EvidenceCaptureDecision?
    var placementFeedback: [EvidencePlacementFeedback] = []
}

