#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/tka-evidence-assets.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -O -parse-as-library \
    "$repo_dir/app/AR/EvidencePlaneOrientation.swift" \
    "$repo_dir/app/AR/EvidenceCaptureMesh.swift" \
    "$repo_dir/app/AR/EvidenceAssetLoader.swift" \
    "$repo_dir/tests/EvidenceAssetChecks.swift" \
    -o "$check_dir/evidence-asset-checks"
"$check_dir/evidence-asset-checks" "$repo_dir"
