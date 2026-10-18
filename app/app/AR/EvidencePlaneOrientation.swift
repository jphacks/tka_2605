import simd

nonisolated enum EvidencePlacementStyle: Sendable {
    case surfaceAligned
    case upright
}

/// Normalize surface poses independently of ARKit's in-plane axes. Upright props
/// and textured sheets use different support axes on floors and tables.
nonisolated enum EvidencePlaneOrientation {
    static func normalSign(planeTransform: simd_float4x4, cameraHeight: Float) -> Float {
        let upward = planeTransform.columns.1.y
        // Props on floors/tables stay on top even if the camera is below a table.
        if abs(upward) > 0.9 { return upward >= 0 ? 1 : -1 }
        return cameraHeight >= 0 ? 1 : -1
    }

    static func normalExtent(size: SIMD3<Float>, modelOrientation: simd_quatf, localRotation: simd_quatf) -> Float {
        let half = size / 2
        return [SIMD3(half.x, 0, 0), SIMD3(0, half.y, 0), SIMD3(0, 0, half.z)]
            .reduce(Float(0)) { $0 + abs(localRotation.act(modelOrientation.act($1)).y) }
    }

    static func localRotation(
        planeTransform: simd_float4x4,
        normalSign: Float,
        style: EvidencePlacementStyle = .surfaceAligned,
        heading: SIMD2<Float>? = nil
    ) -> simd_quatf {
        let planeRotation = simd_float3x3(columns: (
            SIMD3(planeTransform.columns.0.x, planeTransform.columns.0.y, planeTransform.columns.0.z),
            SIMD3(planeTransform.columns.1.x, planeTransform.columns.1.y, planeTransform.columns.1.z),
            SIMD3(planeTransform.columns.2.x, planeTransform.columns.2.y, planeTransform.columns.2.z)
        ))
        let front = simd_normalize(planeRotation.columns.1 * normalSign)
        let worldUp = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(front, worldUp)) > 0.9 {
            // Persist a plane-local heading at placement time. Never follow the
            // live camera afterward, and never inherit ARKit's arbitrary yaw.
            let localHeading = heading.map { SIMD3($0.x, 0, $0.y) } ?? SIMD3(0, 0, 1)
            var towardCamera = planeRotation * localHeading
            towardCamera -= simd_dot(towardCamera, front) * front
            if simd_length_squared(towardCamera) < 0.000001 { towardCamera = planeRotation.columns.2 }
            towardCamera = simd_normalize(towardCamera)
            let up = style == .upright ? front : -towardCamera
            let facing = style == .upright ? towardCamera : front
            let right = simd_normalize(simd_cross(up, facing))
            let worldRotation = simd_float3x3(columns: (right, simd_cross(facing, right), facing))
            return simd_quatf(planeRotation.transpose * worldRotation)
        }
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
