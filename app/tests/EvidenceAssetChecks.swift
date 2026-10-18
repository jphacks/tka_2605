import Foundation
import RealityKit
import simd

/// Standalone checks use the production loader and geometry, including real USDZs.
@main struct EvidenceAssetChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor static func main() async throws {
        try checkGeometry()
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loader = EvidenceAssetLoader()
        var resources = Set<String>()
        for name in ["PersonalEvidenceData", "PhysicalEvidenceData"] {
            let data = try Data(contentsOf: root.appendingPathComponent("app/Data/\(name).json"))
            let records = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            for record in records { resources.insert(record["resourceName"] as! String) }
        }
        for name in resources.sorted() {
            let url = root.appendingPathComponent("Sources/\(name)")
            let asset = try await loader.load(url: url)
            try require(abs(max(asset.size.x, max(asset.size.y, asset.size.z)) - 0.20) < 0.0001,
                        "\(name): longest dimension must be 20cm")
            var samples = 0
            var lower = SIMD3<Float>(repeating: .infinity)
            var upper = SIMD3<Float>(repeating: -.infinity)
            func visit(_ node: Entity) throws {
                if let model = node.components[ModelComponent.self] {
                    let contents = model.mesh.contents
                    for instance in contents.instances {
                        for mesh in contents.models where mesh.id == instance.model {
                            for part in mesh.parts {
                                guard let indices = part.triangleIndices else { continue }
                                let positions = Array(part.positions)
                                let transform = node.transformMatrix(relativeTo: asset.entity) * instance.transform
                                // visualBounds is conservative for rotated child meshes.
                                // Measure rendered vertices to check the actual center.
                                for index in Set(indices) {
                                    let p = positions[Int(index)]
                                    let v = transform * SIMD4(p.x, p.y, p.z, 1)
                                    let point = SIMD3(v.x, v.y, v.z)
                                    lower = simd_min(lower, point)
                                    upper = simd_max(upper, point)
                                }
                                let sampleIndices = Array(indices).prefix(30)
                                for index in sampleIndices {
                                    let p = positions[Int(index)]
                                    let v = transform * SIMD4(p.x, p.y, p.z, 1)
                                    try require(asset.captureMesh.distance(to: SIMD3(v.x, v.y, v.z)) < 0.0001,
                                                "\(name): rendered vertex not on capture surface")
                                    samples += 1
                                }
                            }
                        }
                    }
                }
                for child in node.children { try visit(child) }
            }
            try visit(asset.entity)
            try require(samples > 0, "\(name): no rendered triangle samples")
            try require(simd_length((lower + upper) / 2) < 0.0001, "\(name): render center differs from placement center")
            try require(simd_length(upper - lower - asset.size) < 0.0001, "\(name): render size differs from placement bounds")
            // Cache reuse must return independent entities; changing one must not
            // disable an evidence that reuses the same asset in a later stage.
            asset.entity.isEnabled = false
            let cached = try await loader.load(url: url)
            try require(cached.entity !== asset.entity && cached.entity.isEnabled, "\(name): cache returned shared entity")
            print("PASS \(name): bounds, 20cm scale, \(samples) surface samples, independent cache clone")
        }
        do {
            _ = try await loader.load(resourceName: "missing-evidence.usdz")
            throw Failure(description: "Missing resource was accepted")
        } catch EvidenceAssetLoader.LoadError.missingResource { }
        print("PASS missing resource is reported")
        print("All geometry checks and \(resources.count) real USDZ assets passed")
    }

    static func checkGeometry() throws {
        let box = EvidenceCaptureMesh.box(size: SIMD3(0.1, 0.1, 0.006))
        try require(abs(box.distance(to: SIMD3(0, 0, 0.303)) - 0.30) < 0.00001, "30cm surface threshold")
        try require(box.distance(to: SIMD3(0, 0, 0.3031)) > 0.30, "Outside 30cm threshold")
        try require(abs(box.distance(to: .zero) - 0.003) < 0.00001, "Camera inside solid: nearest actual face")
        try require(abs((box.hitDistance(origin: SIMD3(0, 0, 1), direction: SIMD3(0, 0, -1)) ?? 0) - 0.997) < 0.00001,
                    "Ray hits closest front face")
        try require(box.hitDistance(origin: SIMD3(0, 0, 1), direction: SIMD3(0, 0, 1)) == nil, "Backward ray must miss")
        let triangle = EvidenceCaptureMesh.Triangle(a: SIMD3(0, 0, 0), b: SIMD3(1, 0, 0), c: SIMD3(0, 1, 0))
        let sheet = EvidenceCaptureMesh(triangles: [triangle])
        try require(sheet.hitDistance(origin: SIMD3(0.9, 0.9, 1), direction: SIMD3(0, 0, -1)) == nil,
                    "Bounding box empty space is not selectable")
        try require(sheet.distance(to: SIMD3(0.9, 0.9, 0)) > 0.5, "Distance uses triangle, not bounding box")
        try require(sheet.hitDistance(origin: SIMD3(0.2, 0.2, -1), direction: SIMD3(0, 0, 1)) != nil,
                    "Thin sheet can be selected from back")
        let collapsed = EvidenceCaptureMesh(triangles: [.init(a: .zero, b: SIMD3(1, 0, 0), c: SIMD3(1, 0, 0))])
        try require(abs(collapsed.distance(to: SIMD3(0.5, 0.3, 0)) - 0.3) < 0.00001, "Collapsed triangle handled safely")
        // More than 16 faces exercises BVH branches, far nodes and the closest hit.
        let separated = EvidenceCaptureMesh(triangles: (0..<100).map { index in
            let offset = SIMD3<Float>(0, 0, Float(index))
            return .init(a: triangle.a + offset, b: triangle.b + offset, c: triangle.c + offset)
        })
        try require(abs(separated.distance(to: SIMD3(0.2, 0.2, 50.4)) - 0.4) < 0.0001, "BVH closest distance")
        try require(abs((separated.hitDistance(origin: SIMD3(0.2, 0.2, 100), direction: SIMD3(0, 0, -1)) ?? 0) - 1) < 0.0001,
                    "BVH closest intersection")
        let empty = EvidenceCaptureMesh(triangles: [])
        try require(empty.distance(to: .zero).isInfinite && empty.hitDistance(origin: .zero, direction: SIMD3(0, 0, 1)) == nil,
                    "Empty geometry cannot be captured")
        print("PASS geometry: surface thresholds, mesh gaps, two-sided picking, degenerate faces, BVH, empty input")
    }
}
