import SwiftUI
import UIKit

struct StorySceneView: View {
    let statement: Story.Statement
    let speakerName: String?
    let playbackID: UUID
    let isTextRevealed: Bool
    let isHost: Bool
    let isReady: Bool
    let onReveal: () -> Void
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var displayedCharacterCount = 0
    @State private var displayedScene: SceneID?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                StoryResourceImage(resourceName: statement.resourceName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)

                dialogue
                    .frame(height: dialogueHeight(in: geometry.size.height))
            }
            .padding(.horizontal, geometry.size.width > 600 ? 32 : 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: typingTaskID) {
            await typeStatement()
        }
    }

    private var dialogue: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if statement.personID != 0, let speakerName, !speakerName.isEmpty {
                    Text(speakerName)
                        .font(.headline)
                        .foregroundStyle(.tint)
                }

                Text(visibleStatement.isEmpty ? " " : visibleStatement)
                    .font(.title3)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(interactionHint)
                        .font(.caption)
                    if isHost && isStatementComplete {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 840)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture(perform: handleTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleStatement)
        .accessibilityHint(interactionHint)
        .accessibilityAddTraits(isHost ? .isButton : .isStaticText)
        .accessibilityAction {
            handleTap()
        }
    }

    private var sceneID: SceneID {
        SceneID(playbackID: playbackID, statementID: statement.id, text: statement.statement)
    }

    private var typingTaskID: TypingTaskID {
        TypingTaskID(
            scene: sceneID,
            isRevealed: isTextRevealed,
            isReady: isReady,
            skipTyping: reduceMotion || voiceOverEnabled
        )
    }

    private var visibleStatement: String {
        if isTextRevealed || reduceMotion || voiceOverEnabled {
            return statement.statement
        }
        guard displayedScene == sceneID else { return "" }
        return String(statement.statement.prefix(displayedCharacterCount))
    }

    private var isStatementComplete: Bool {
        isTextRevealed || reduceMotion || voiceOverEnabled
            || (displayedScene == sceneID && displayedCharacterCount >= statement.statement.count)
    }

    private var interactionHint: String {
        guard isHost else { return "ホストの操作を待っています" }
        return isStatementComplete ? "タップして次へ" : "タップして全文を表示"
    }

    private var accessibleStatement: String {
        if statement.personID != 0, let speakerName, !speakerName.isEmpty {
            return "\(speakerName)。\(statement.statement)"
        }
        return statement.statement
    }

    private func dialogueHeight(in height: CGFloat) -> CGFloat {
        let availableHeight = max(0, height - 60)
        let fraction = dynamicTypeSize.isAccessibilitySize ? 0.65 : 0.4
        return min(availableHeight, max(160, availableHeight * fraction))
    }

    private func handleTap() {
        guard isHost, isReady else { return }
        if isStatementComplete {
            onAdvance()
        } else {
            onReveal()
        }
    }

    @MainActor
    private func typeStatement() async {
        guard !Task.isCancelled else { return }
        let activeScene = sceneID
        if displayedScene != activeScene {
            displayedScene = activeScene
            displayedCharacterCount = 0
        }
        if isTextRevealed || reduceMotion || voiceOverEnabled {
            displayedCharacterCount = statement.statement.count
            return
        }
        guard isReady else { return }

        let characterCount = statement.statement.count
        while displayedCharacterCount < characterCount {
            do {
                try await Task.sleep(for: .milliseconds(30))
            } catch {
                return
            }
            guard !Task.isCancelled, displayedScene == activeScene else { return }
            displayedCharacterCount += 1
        }
    }

    private struct SceneID: Hashable {
        let playbackID: UUID
        let statementID: UUID
        let text: String
    }

    private struct TypingTaskID: Hashable {
        let scene: SceneID
        let isRevealed: Bool
        let isReady: Bool
        let skipTyping: Bool
    }
}

private struct StoryResourceImage: View {
    let resourceName: String

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.secondary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .frame(maxWidth: 560)
            }
        }
    }

    private func loadImage() -> UIImage? {
        guard !resourceName.isEmpty else { return nil }
        if let image = UIImage(named: resourceName) {
            return image
        }

        let name = resourceName as NSString
        let fileExtension = name.pathExtension
        let basename = fileExtension.isEmpty ? resourceName : name.deletingPathExtension
        if !fileExtension.isEmpty, let image = UIImage(named: basename) {
            return image
        }

        let extensions = fileExtension.isEmpty ? ["png", "jpg", "jpeg", "heic", "webp"] : [fileExtension]
        for candidate in extensions {
            if let url = Bundle.main.url(forResource: basename, withExtension: candidate),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
}
