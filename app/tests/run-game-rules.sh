#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness_dir="$(mktemp -d /private/tmp/tka-game-rules.XXXXXX)"
mkdir -p "$harness_dir/Sources/GameRules" "$harness_dir/Tests/GameRulesTests"

# Compile the application's actual rules, managers and API classes. Playgrounds
# are excluded; the API's lazy static JSON is not accessed by these fixtures.
cp "$repo_dir/app/Models/Models.swift" "$harness_dir/Sources/GameRules/Models.swift"
cp "$repo_dir/app/Models/GameModels.swift" "$harness_dir/Sources/GameRules/GameModels.swift"
for api in EpisodeAPI EvidenceDataAPI PersonDataAPI StoryData; do
    awk '/^import Playgrounds/ { exit } { print }' \
        "$repo_dir/app/API/$api.swift" > "$harness_dir/Sources/GameRules/$api.swift"
done
cp "$repo_dir/app/API/EpisodeDataResolver.swift" "$harness_dir/Sources/GameRules/EpisodeDataResolver.swift"
for manager in GameManager EpisodeManager PlayerManager ScreenManager; do
    cp "$repo_dir/app/Manager/$manager.swift" "$harness_dir/Sources/GameRules/$manager.swift"
done
cp "$repo_dir/app/Logic/JsonLoader.swift" "$harness_dir/Sources/GameRules/JsonLoader.swift"
awk '/^@Observable/ { exit } { print }' \
    "$repo_dir/app/Manager/PeerManager.swift" > "$harness_dir/Sources/GameRules/GameMessage.swift"
cp "$repo_dir/app/AR/EvidencePlaneOrientation.swift" "$harness_dir/Sources/GameRules/EvidencePlaneOrientation.swift"
for source in EvidenceARComponents EvidenceARGeometry EvidenceCaptureMesh EvidencePlacementEngine; do
    cp "$repo_dir/app/AR/$source.swift" "$harness_dir/Sources/GameRules/$source.swift"
done
cp "$repo_dir/tests/support/FakePeerManager.swift" "$harness_dir/Sources/GameRules/FakePeerManager.swift"
cp "$repo_dir/tests/support/FakeEvidenceARRuntime.swift" "$harness_dir/Sources/GameRules/FakeEvidenceARRuntime.swift"
cp "$repo_dir/app/Presentation/Game/GameViewModel.swift" "$harness_dir/Sources/GameRules/GameViewModel.swift"
cp "$repo_dir/app/Presentation/Game/EvidenceSearchAssistance.swift" "$harness_dir/Sources/GameRules/EvidenceSearchAssistance.swift"
cp "$repo_dir/tests/GameRulesTests.swift" "$repo_dir/tests/GameManagerTests.swift" \
    "$repo_dir/tests/GameFixtures.swift" "$repo_dir/tests/EvidenceOrientationTests.swift" \
    "$repo_dir/tests/EpisodeDataTests.swift" "$repo_dir/tests/StoryPlaybackTests.swift" \
    "$repo_dir/tests/EvidenceSearchAssistanceTests.swift" "$repo_dir/tests/GameSearchAssistanceTests.swift" \
    "$repo_dir/tests/EvidencePlacementTests.swift" \
    "$harness_dir/Tests/GameRulesTests/"
mkdir -p "$harness_dir/Tests/GameRulesTests/Resources"
cp "$repo_dir"/app/Data/*.json "$harness_dir/Tests/GameRulesTests/Resources/"

cat > "$harness_dir/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GameRules",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GameRules"),
        .testTarget(name: "GameRulesTests", dependencies: ["GameRules"], resources: [.copy("Resources")])
    ]
)
PACKAGE

printf 'Game rules harness: %s\n' "$harness_dir"
CLANG_MODULE_CACHE_PATH="$harness_dir/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$harness_dir/ModuleCache" \
swift test \
    --package-path "$harness_dir" \
    --cache-path "$harness_dir/Cache" \
    --config-path "$harness_dir/Config" \
    --security-path "$harness_dir/Security" \
    --scratch-path "$harness_dir/.build" \
    --manifest-cache local \
    --disable-keychain \
    --disable-netrc \
    --disable-sandbox \
    "$@"
