import Foundation
import RealityKit

@MainActor
enum EvidenceARGeometry {
    static func surfaceDistanceSquared(camera: SIMD4<Float>, surface: RecognizedSurfaceComponent) -> Float {
        guard surface.boundary.count >= 3 else { return .infinity }
        let local = surface.transform.inverse * camera
        let point = SIMD2(local.x, local.z)
        if contains(point, polygon: surface.boundary) { return local.y * local.y }
        var nearest = Float.infinity
        for index in surface.boundary.indices {
            let start = surface.boundary[index]
            let edge = surface.boundary[(index + 1) % surface.boundary.count] - start
            let length = simd_length_squared(edge)
            let fraction = length > 0 ? min(1, max(0, simd_dot(point - start, edge) / length)) : 0
            nearest = min(nearest, simd_distance_squared(point, start + fraction * edge))
        }
        return nearest + local.y * local.y
    }

    static func hitDistance(_ entity: Entity, origin: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        guard entity.components[EvidencePlacementComponent.self]?.isValid == true,
              let model = entity.components[EvidenceComponent.self]?.model else { return nil }
        let localOrigin = model.orientation.inverse.act(entity.convert(position: origin, from: nil))
        let localDirection = model.orientation.inverse.act(entity.convert(direction: direction, from: nil))
        return model.captureMesh.hitDistance(origin: localOrigin, direction: localDirection)
    }

    static func canCapture(_ entity: Entity, input: EvidenceARInputComponent) -> Bool {
        guard input.interactionEnabled, input.photographing, input.trackingNormal,
              input.viewportSize.width > 0, input.viewportSize.height > 0,
              abs(input.viewportSize.width / input.viewportSize.height - 1) < 0.02,
              entity.components[EvidencePlacementComponent.self]?.isValid == true,
              let evidence = entity.components[EvidenceComponent.self]
        else { return false }

        let camera = input.cameraTransform.columns.3
        let pointInRoot = entity.convert(position: SIMD3(camera.x, camera.y, camera.z), from: nil)
        let pointInModel = evidence.model.orientation.inverse.act(pointInRoot)
        let distance = evidence.model.captureMesh.distance(to: pointInModel)
        guard distance <= 0.30 else { return false }

        // Use the very same viewport projection as the 1:1 ARView that is snapshotted.
        let center = entity.position(relativeTo: nil)
        let clip = input.viewProjection * SIMD4(center.x, center.y, center.z, 1)
        return clip.w > 0 && abs(clip.x) <= clip.w && abs(clip.y) <= clip.w
    }

    static func worldTransform(
        _ placement: EvidencePlacementComponent,
        model: EvidenceModelConfiguration,
        surface: RecognizedSurfaceComponent
    ) -> simd_float4x4 {
        let rotation = EvidencePlaneOrientation.localRotation(
            planeTransform: surface.transform,
            normalSign: placement.normalSign,
            style: model.placementStyle,
            heading: placement.surfaceHeading
        )
        // Lift the body slightly off the recognized plane to avoid z-fighting.
        let normalExtent = EvidencePlaneOrientation.normalExtent(
            size: model.size, modelOrientation: model.orientation, localRotation: rotation
        )
        let offset = normalExtent + 0.002
        let local = Transform(
            rotation: rotation,
            translation: SIMD3(placement.planePosition.x, placement.normalSign * offset, placement.planePosition.y)
        ).matrix
        return surface.transform * local
    }

    static func fits(
        _ model: EvidenceModelConfiguration,
        at position: SIMD2<Float>,
        sign: Float,
        in surface: RecognizedSurfaceComponent,
        heading: SIMD2<Float>? = nil
    ) -> Bool {
        guard surface.boundary.count >= 3 else { return false }
        let rotation = EvidencePlaneOrientation.localRotation(planeTransform: surface.transform, normalSign: sign,
                                                              style: model.placementStyle, heading: heading)
        let half = model.size / 2
        var corners: [SIMD2<Float>] = []
        for x: Float in [-half.x, half.x] {
            for y: Float in [-half.y, half.y] {
                for z: Float in [-half.z, half.z] {
                    let point = rotation.act(model.orientation.act(SIMD3(x, y, z)))
                    corners.append(position + SIMD2(point.x, point.z))
                }
            }
        }
        let footprint = convexHull(corners)
        guard footprint.allSatisfy({ contains($0, polygon: surface.boundary) }) else { return false }

        // Checking just the corners is insufficient for a concave recognized boundary.
        for index in footprint.indices {
            let start = footprint[index]
            let end = footprint[(index + 1) % footprint.count]
            var cuts: [Float] = [0, 1]
            for boundaryIndex in surface.boundary.indices {
                let a = surface.boundary[boundaryIndex]
                let b = surface.boundary[(boundaryIndex + 1) % surface.boundary.count]
                if let t = intersectionParameter(start, end, a, b) { cuts.append(t) }
            }
            cuts.sort()
            for cutIndex in 1..<cuts.count {
                let middle = (cuts[cutIndex - 1] + cuts[cutIndex]) / 2
                if !contains(start + (end - start) * middle, polygon: surface.boundary) { return false }
            }
        }
        return true
    }

    static func candidates(
        in surface: RecognizedSurfaceComponent,
        model: EvidenceModelConfiguration,
        sign: Float,
        near camera: SIMD2<Float>
    ) -> [SIMD2<Float>] {
        guard let first = surface.boundary.first else { return [] }
        let lower = surface.boundary.reduce(first) { simd_min($0, $1) }
        let upper = surface.boundary.reduce(first) { simd_max($0, $1) }
        guard lower.x.isFinite, lower.y.isFinite, upper.x.isFinite, upper.y.isFinite else { return [] }
        let half = model.size / 2
        let rotation = EvidencePlaneOrientation.localRotation(
            planeTransform: surface.transform, normalSign: sign, style: model.placementStyle,
            heading: camera - (lower + upper) / 2
        )
        var footprintExtent = SIMD2<Float>.zero
        for axis in [SIMD3(half.x, 0, 0), SIMD3(0, half.y, 0), SIMD3(0, 0, half.z)] {
            let rotated = rotation.act(model.orientation.act(axis))
            footprintExtent += SIMD2(abs(rotated.x), abs(rotated.z))
        }
        let innerLower = lower + footprintExtent
        let innerUpper = upper - footprintExtent
        guard innerLower.x <= innerUpper.x, innerLower.y <= innerUpper.y else { return [] }
        var points: [SIMD2<Float>] = []
        // Sample the entire detected polygon; never clamp its height or invent a larger plane.
        // Include interior midlines and inset edges so a narrow but usable wall is
        // not accidentally missed by a grid whose first sample lies on its boundary.
        func coordinates(lower: Float, upper: Float, near camera: Float) -> [Float] {
            var values = [lower, upper, (lower + upper) / 2, min(upper, max(lower, camera))]
            for index in 0...Int(floor((upper - lower) / 0.25)) {
                values.append(lower + Float(index) * 0.25)
            }
            return Array(Set(values)).sorted()
        }
        let xs = coordinates(lower: innerLower.x, upper: innerUpper.x, near: camera.x)
        let ys = coordinates(lower: innerLower.y, upper: innerUpper.y, near: camera.y)
        for x in xs {
            for y in ys { points.append(SIMD2(x, y)) }
        }
        return points.sorted { simd_distance_squared($0, camera) < simd_distance_squared($1, camera) }
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    private static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var lower: [SIMD2<Float>] = []
        var upper: [SIMD2<Float>] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 1] - lower[lower.count - 2], point - lower[lower.count - 1]) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 1] - upper[upper.count - 2], point - upper[upper.count - 1]) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    private static func contains(_ point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        var inside = false
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let edge = b - a
            let lengthSquared = simd_length_squared(edge)
            let t = lengthSquared > 0 ? min(1, max(0, simd_dot(point - a, edge) / lengthSquared)) : 0
            if simd_distance_squared(point, a + t * edge) <= 0.00000001 { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
        }
        return inside
    }

    private static func intersectionParameter(
        _ start: SIMD2<Float>, _ end: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>
    ) -> Float? {
        let r = end - start
        let s = b - a
        let denominator = cross(r, s)
        guard abs(denominator) > 0.000001 else { return nil }
        let t = cross(a - start, s) / denominator
        let u = cross(a - start, r) / denominator
        return (0...1).contains(t) && (0...1).contains(u) ? t : nil
    }
}
