import simd

/// The rendered triangles, in the evidence root's coordinates. Labels and badges
/// are deliberately excluded. A BVH keeps surface distance and picking practical
/// even for detailed assets such as the stand light.
nonisolated struct EvidenceCaptureMesh: Sendable {
    struct Triangle: Sendable {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        var center: SIMD3<Float> { (a + b + c) / 3 }
    }

    private struct Node: Sendable {
        let lower: SIMD3<Float>
        let upper: SIMD3<Float>
        let range: Range<Int>
        var left = -1
        var right = -1
    }

    private var triangles: [Triangle]
    private var nodes: [Node] = []

    init(triangles: [Triangle]) {
        self.triangles = triangles
        if !triangles.isEmpty { _ = build(0..<triangles.count) }
    }

    static func box(size: SIMD3<Float>) -> Self {
        let h = size / 2
        let vertices = [SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z),
                        SIMD3(h.x, h.y, -h.z), SIMD3(-h.x, h.y, -h.z),
                        SIMD3(-h.x, -h.y, h.z), SIMD3(h.x, -h.y, h.z),
                        SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z)]
        let indices = [0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4,
                       3,7,6, 3,6,2, 0,4,7, 0,7,3, 1,2,6, 1,6,5]
        return Self(triangles: stride(from: 0, to: indices.count, by: 3).map {
            Triangle(a: vertices[indices[$0]], b: vertices[indices[$0 + 1]], c: vertices[indices[$0 + 2]])
        })
    }

    func distance(to point: SIMD3<Float>) -> Float {
        guard !nodes.isEmpty else { return .infinity }
        var best = Float.infinity
        var stack = [0]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard boxDistanceSquared(point, node) <= best else { continue }
            if node.left < 0 {
                for index in node.range {
                    best = min(best, Self.distanceSquared(point, triangles[index]))
                }
            } else {
                let leftDistance = boxDistanceSquared(point, nodes[node.left])
                let rightDistance = boxDistanceSquared(point, nodes[node.right])
                // Visit the nearer subtree first, tightening the bound early.
                stack.append(leftDistance < rightDistance ? node.right : node.left)
                stack.append(leftDistance < rightDistance ? node.left : node.right)
            }
        }
        return sqrt(best)
    }

    /// Double sided: thin sheets remain selectable from either visible side.
    func hitDistance(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        guard !nodes.isEmpty, simd_length_squared(direction) > 0 else { return nil }
        var best = Float.infinity
        var stack = [0]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard intersects(node, origin: origin, direction: direction, limit: best) else { continue }
            if node.left < 0 {
                for index in node.range {
                    let triangle = triangles[index]
                    let e1 = triangle.b - triangle.a
                    let e2 = triangle.c - triangle.a
                    let p = simd_cross(direction, e2)
                    let determinant = simd_dot(e1, p)
                    guard abs(determinant) > 1e-12 else { continue }
                    let inverse = 1 / determinant
                    let offset = origin - triangle.a
                    let u = simd_dot(offset, p) * inverse
                    guard u >= 0, u <= 1 else { continue }
                    let q = simd_cross(offset, e1)
                    let v = simd_dot(direction, q) * inverse
                    guard v >= 0, u + v <= 1 else { continue }
                    let distance = simd_dot(e2, q) * inverse
                    if distance >= 0 { best = min(best, distance) }
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }
        return best.isFinite ? best : nil
    }

    private mutating func build(_ range: Range<Int>) -> Int {
        var lower = SIMD3<Float>(repeating: .infinity)
        var upper = SIMD3<Float>(repeating: -.infinity)
        for index in range {
            let triangle = triangles[index]
            lower = simd_min(lower, simd_min(triangle.a, simd_min(triangle.b, triangle.c)))
            upper = simd_max(upper, simd_max(triangle.a, simd_max(triangle.b, triangle.c)))
        }
        let index = nodes.count
        nodes.append(Node(lower: lower, upper: upper, range: range))
        if range.count > 16 {
            let extent = upper - lower
            let axis = extent.x >= extent.y && extent.x >= extent.z ? 0 : (extent.y >= extent.z ? 1 : 2)
            triangles[range].sort { $0.center[axis] < $1.center[axis] }
            let middle = range.lowerBound + range.count / 2
            let left = build(range.lowerBound..<middle)
            let right = build(middle..<range.upperBound)
            nodes[index].left = left
            nodes[index].right = right
        }
        return index
    }

    private func boxDistanceSquared(_ point: SIMD3<Float>, _ node: Node) -> Float {
        let delta = simd_max(simd_max(node.lower - point, point - node.upper), .zero)
        return simd_length_squared(delta)
    }

    private func intersects(_ node: Node, origin: SIMD3<Float>, direction: SIMD3<Float>, limit: Float) -> Bool {
        var near: Float = 0
        var far = limit
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-10 {
                if origin[axis] < node.lower[axis] || origin[axis] > node.upper[axis] { return false }
            } else {
                let a = (node.lower[axis] - origin[axis]) / direction[axis]
                let b = (node.upper[axis] - origin[axis]) / direction[axis]
                near = max(near, min(a, b))
                far = min(far, max(a, b))
                if near > far { return false }
            }
        }
        return true
    }

    private static func distanceSquared(_ p: SIMD3<Float>, _ t: Triangle) -> Float {
        let ab = t.b - t.a
        let ac = t.c - t.a
        // Imported meshes can contain collapsed faces. Measure their edges safely.
        if simd_length_squared(simd_cross(ab, ac)) < 1e-20 {
            return min(segmentDistanceSquared(p, t.a, t.b),
                       min(segmentDistanceSquared(p, t.b, t.c), segmentDistanceSquared(p, t.c, t.a)))
        }
        let ap = p - t.a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return simd_length_squared(ap) }
        let bp = p - t.b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return simd_length_squared(bp) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            return simd_length_squared(p - (t.a + (d1 / (d1 - d3)) * ab))
        }
        let cp = p - t.c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return simd_length_squared(cp) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            return simd_length_squared(p - (t.a + (d2 / (d2 - d6)) * ac))
        }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 {
            return simd_length_squared(p - (t.b + ((d4 - d3) / ((d4 - d3) + (d5 - d6))) * (t.c - t.b)))
        }
        let denominator = 1 / (va + vb + vc)
        return simd_length_squared(p - (t.a + ab * (vb * denominator) + ac * (vc * denominator)))
    }

    private static func segmentDistanceSquared(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let edge = b - a
        let length = simd_length_squared(edge)
        let fraction = length > 0 ? min(1, max(0, simd_dot(p - a, edge) / length)) : 0
        return simd_length_squared(p - (a + fraction * edge))
    }
}
