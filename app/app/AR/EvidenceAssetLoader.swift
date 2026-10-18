import Foundation
import RealityKit
import simd

nonisolated struct EvidenceAssetConfiguration: Sendable {
    /// Imported assets use different authoring scales. Keep investigation props
    /// approachable; individual assets can override their size and pose here.
    var maximumDimension: Float = 0.20
    var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))

    static func configuration(resourceName: String) -> Self {
        var result = Self()
        switch URL(fileURLWithPath: resourceName).lastPathComponent.lowercased() {
        case "book.usdz", "chest.usdz", "window.usdz":
            // These Z-up assets stand against vertical surfaces. The evidence
            // root uses Y for upright and +Z for the camera-facing plane normal.
            result.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        default:
            // Sheets already lie in XY; the lamp/person stand along +Z on a
            // horizontal surface. Both match the evidence root's +Z normal.
            break
        }
        return result
    }
}

@MainActor
final class EvidenceAssetLoader {
    struct Asset {
        let entity: Entity
        let size: SIMD3<Float>
        let captureMesh: EvidenceCaptureMesh
    }

    enum LoadError: LocalizedError {
        case missingResource(String)
        case invalidGeometry(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): return "モデルが見つかりません: \(name)"
            case .invalidGeometry(let name): return "モデルの形状を読み込めません: \(name)"
            }
        }
    }

    private struct MeshPart: Sendable {
        let positions: [SIMD3<Float>]
        let indices: [UInt32]
        let transform: simd_float4x4
    }

    private var cache: [URL: Asset] = [:]

    func load(resourceName: String, bundle: Bundle = .main) async throws -> Asset {
        let path = resourceName as NSString
        let file = path.deletingPathExtension
        let ext = path.pathExtension
        guard let url = bundle.url(forResource: file, withExtension: ext)
            ?? bundle.url(forResource: file, withExtension: ext, subdirectory: "Sources")
        else { throw LoadError.missingResource(resourceName) }
        return try await load(url: url)
    }

    func load(url: URL) async throws -> Asset {
        if let cached = cache[url] {
            return Asset(entity: cached.entity.clone(recursive: true), size: cached.size, captureMesh: cached.captureMesh)
        }
        let imported = try await Entity(contentsOf: url)
        try Task.checkCancellation()
        // Keep authored materials/mesh transforms, excluding authoring cameras,
        // lights, physics and animation that must not drive the game's AR scene.
        let body = copyVisualHierarchy(imported)
        let configuration = EvidenceAssetConfiguration.configuration(resourceName: url.lastPathComponent)
        let rotation = simd_float4x4(configuration.rotation)
        var parts: [MeshPart] = []
        func visit(_ node: Entity) {
            if let model = node.components[ModelComponent.self] {
                let contents = model.mesh.contents
                for instance in contents.instances {
                    for mesh in contents.models where mesh.id == instance.model {
                        for part in mesh.parts {
                            guard let indices = part.triangleIndices else { continue }
                            parts.append(MeshPart(
                                positions: Array(part.positions),
                                indices: Array(indices),
                                transform: rotation * body.transform.matrix * node.transformMatrix(relativeTo: body) * instance.transform
                            ))
                        }
                    }
                }
            }
            for child in node.children { visit(child) }
        }
        visit(body)
        let meshParts = parts
        let geometryTask = Task.detached(priority: .userInitiated) {
            try Self.prepare(parts: meshParts, configuration: configuration, name: url.lastPathComponent)
        }
        let prepared = try await withTaskCancellationHandler {
            try await geometryTask.value
        } onCancel: {
            geometryTask.cancel()
        }
        try Task.checkCancellation()
        let oriented = Entity()
        oriented.orientation = configuration.rotation
        oriented.scale = SIMD3(repeating: prepared.scale)
        oriented.position = -prepared.center * prepared.scale
        oriented.addChild(body)
        let normalized = Entity()
        normalized.addChild(oriented)
        let asset = Asset(entity: normalized, size: prepared.size, captureMesh: prepared.mesh)
        cache[url] = asset
        return Asset(entity: normalized.clone(recursive: true), size: asset.size, captureMesh: asset.captureMesh)
    }

    private func copyVisualHierarchy(_ source: Entity) -> Entity {
        let copy = Entity()
        copy.name = source.name
        copy.transform = source.transform
        if let model = source.components[ModelComponent.self] { copy.components.set(model) }
        for child in source.children { copy.addChild(copyVisualHierarchy(child)) }
        return copy
    }

    nonisolated private static func prepare(
        parts: [MeshPart], configuration: EvidenceAssetConfiguration, name: String
    ) throws -> (mesh: EvidenceCaptureMesh, size: SIMD3<Float>, center: SIMD3<Float>, scale: Float) {
        var triangles: [EvidenceCaptureMesh.Triangle] = []
        var lower = SIMD3<Float>(repeating: .infinity)
        var upper = SIMD3<Float>(repeating: -.infinity)
        for part in parts {
            try Task.checkCancellation()
            let positions = part.positions.map { position -> SIMD3<Float> in
                let point = part.transform * SIMD4(position.x, position.y, position.z, 1)
                return SIMD3(point.x, point.y, point.z)
            }
            guard part.indices.count.isMultiple(of: 3) else { throw LoadError.invalidGeometry(name) }
            for index in stride(from: 0, to: part.indices.count, by: 3) {
                let indices = (0..<3).map { Int(part.indices[index + $0]) }
                guard indices.allSatisfy({ positions.indices.contains($0) }) else {
                    throw LoadError.invalidGeometry(name)
                }
                let a = positions[indices[0]], b = positions[indices[1]], c = positions[indices[2]]
                guard [a, b, c].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
                    throw LoadError.invalidGeometry(name)
                }
                lower = simd_min(lower, simd_min(a, simd_min(b, c)))
                upper = simd_max(upper, simd_max(a, simd_max(b, c)))
                triangles.append(.init(a: a, b: b, c: c))
            }
        }
        let extent = upper - lower
        let maximum = max(extent.x, max(extent.y, extent.z))
        guard !triangles.isEmpty, maximum.isFinite, maximum > 0,
              configuration.maximumDimension > 0 else { throw LoadError.invalidGeometry(name) }
        let center = (upper + lower) / 2
        let scale = configuration.maximumDimension / maximum
        for index in triangles.indices {
            if index.isMultiple(of: 4096) { try Task.checkCancellation() }
            let t = triangles[index]
            triangles[index] = .init(a: (t.a - center) * scale,
                                     b: (t.b - center) * scale, c: (t.c - center) * scale)
        }
        let mesh = EvidenceCaptureMesh(triangles: triangles)
        try Task.checkCancellation()
        return (mesh, extent * scale, center, scale)
    }
}
