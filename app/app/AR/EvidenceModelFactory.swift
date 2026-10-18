import RealityKit
import UIKit

@MainActor
final class EvidenceModelFactory {
    static let visualName = EvidenceEntityNames.visual
    static let collectedName = EvidenceEntityNames.collected
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
            configuration.placementStyle = asset.placementStyle
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
