import ARKit
import RealityKit
import UIKit

/// AR coordinates and the photos stay on this device. Only EvidenceKey crosses the network.
nonisolated struct EvidenceComponent: Component {
    let key: EvidenceKey
    let name: String
    let requiredSurface: EvidenceSurfaceClassification?
    let model: EvidenceModelConfiguration
    var isCollected: Bool
}

/// Bounds control placement; the rendered mesh controls picking and surface distance.
nonisolated struct EvidenceModelConfiguration {
    var size: SIMD3<Float> = SIMD3(0.10, 0.10, 0.006)
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
    var captureMesh = EvidenceCaptureMesh.box(size: SIMD3(0.10, 0.10, 0.006))
}

/// Keep the label upright independently of ARKit's in-plane anchor axes. Flipping
/// the visible face reverses the right axis, rather than turning the text upside down.
nonisolated enum EvidencePlaneOrientation {
    static func localRotation(planeTransform: simd_float4x4, normalSign: Float) -> simd_quatf {
        let planeRotation = simd_float3x3(columns: (
            SIMD3(planeTransform.columns.0.x, planeTransform.columns.0.y, planeTransform.columns.0.z),
            SIMD3(planeTransform.columns.1.x, planeTransform.columns.1.y, planeTransform.columns.1.z),
            SIMD3(planeTransform.columns.2.x, planeTransform.columns.2.y, planeTransform.columns.2.z)
        ))
        let front = simd_normalize(planeRotation.columns.1 * normalSign)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var up = worldUp - simd_dot(worldUp, front) * front
        if simd_length_squared(up) < 0.000001 {
            // Gravity has no direction along a horizontal plane. Use its -Z tangent
            // consistently on either face instead of normalizing a zero vector.
            let tangent = -planeRotation.columns.2
            up = tangent - simd_dot(tangent, front) * front
        }
        up = simd_normalize(up)
        let right = simd_normalize(simd_cross(up, front))
        let worldRotation = simd_float3x3(columns: (right, simd_cross(front, right), front))
        return simd_quatf(planeRotation.transpose * worldRotation)
    }
}

nonisolated enum EvidenceSurfaceClassification: String {
    case wall, floor, ceiling, table, seat, window, door

    init?(dataValue: String) {
        self.init(rawValue: dataValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

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
    var isValid = false
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
}

@MainActor
final class EvidenceModelFactory {
    static let visualName = "evidence-visual"
    static let collectedName = "collected-indicator"
    private let assetLoader = EvidenceAssetLoader()

    func make(evidence: Evidence, key: EvidenceKey) async throws -> Entity {
        var configuration = EvidenceModelConfiguration()
        let visual = Entity()
        visual.name = Self.visualName
        if evidence.modelResourceName.isEmpty {
            let body = ModelEntity(
                mesh: .generateBox(size: configuration.size),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.94, blue: 0.78, alpha: 1))]
            )
            visual.addChild(body)
            if let label = Self.makeLabel(evidence.name, size: configuration.size) {
                visual.addChild(label)
            }
        } else {
            let asset = try await assetLoader.load(resourceName: evidence.modelResourceName)
            configuration.size = asset.size
            configuration.captureMesh = asset.captureMesh
            visual.addChild(asset.entity)
        }
        visual.orientation = configuration.orientation
        let root = Entity()
        root.name = "evidence-\(key.kind)-\(key.id)"
        root.components.set(EvidenceComponent(
            key: key,
            name: evidence.name,
            requiredSurface: EvidenceSurfaceClassification(dataValue: evidence.classification),
            model: configuration,
            isCollected: evidence.isCollected
        ))
        root.components.set(EvidencePlacementComponent())

        let collected = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.018, 0.008, 0.002)),
            materials: [UnlitMaterial(color: .systemGreen)]
        )
        collected.name = Self.collectedName
        collected.position = SIMD3(0, -configuration.size.y * 0.38, configuration.size.z / 2 + 0.001)
        collected.isEnabled = evidence.isCollected
        visual.addChild(collected)
        visual.isEnabled = false
        root.addChild(visual)
        return root
    }

    private static func makeLabel(_ name: String, size: SIMD3<Float>) -> ModelEntity? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let labelImage = renderer.image { context in
            UIColor(red: 1, green: 0.94, blue: 0.78, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byCharWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            let text = name as NSString
            let textRect = CGRect(x: 24, y: 40, width: 464, height: 400)
            let bounds = text.boundingRect(
                with: textRect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            text.draw(
                with: CGRect(x: 24, y: (512 - min(bounds.height, 400)) / 2, width: 464, height: 400),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }
        guard let cgImage = labelImage.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else { return nil }

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        let label = ModelEntity(
            mesh: .generatePlane(width: size.x, height: size.y),
            materials: [material]
        )
        label.position.z = size.z / 2 + 0.0002
        return label
    }
}
