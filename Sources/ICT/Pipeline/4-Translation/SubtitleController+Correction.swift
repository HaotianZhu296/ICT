import Foundation
import ICTCore

/// 用 Google、Apple 翻译时的“自动纠正口音”：识别困难期间，大模型只纠正原文，译文还是 Google、Apple 出。
/// 每句先显示 Google 译文；纠错会话回 `=` 就不动，回了纠正后的原文就原地换掉原文、用 Google 重新翻译。
/// 以前让 Claude 连带翻译每一句，2026-10-28 实测花费约为现在的 6 倍。
/// 字幕记录只能追加，所以等纠错的句子先不写进记录（`SubtitleLine.correctionPending`）。
extension SubtitleController {
    /// 纠错跟不上时（排队超过这么多句）新句子不再纠正，免得字幕记录越拖越晚。
    static let maxPendingCorrections = 3

    func makeCorrector(_ model: ModelChoice) throws -> ChatSession {
        let session = try ChatSessionFactory.make(
            model, settings: settings, systemPrompt: Prompts.correctorSystemPrompt(source: settings.source),
            maxTurns: 40, historyTurns: 12, timeout: 25)
        session.warmUp()
        return session
    }

    /// 把这句排进纠错队列。会话带着前文，请求要按顺序一句一句来。
    func requestCorrection(_ id: UUID, source: String) {
        guard let corrector, pendingCorrections < Self.maxPendingCorrections, let i = index(of: id) else { return }
        lines[i].correctionPending = true
        pendingCorrections += 1
        let context = lines[..<i].suffix(6).map(\.source)
        let previous = correctionTail
        correctionTail = Task {
            await previous?.value
            var corrected: String?
            do {
                let reply = try await corrector.request(
                    newSessionMessage: Prompts.correctionMessage(text: source, context: context),
                    ongoingMessage: source, onPartial: { _ in })
                corrected = CorrectionOutput.parse(reply, original: source)
            } catch {
                appLog.error("correct failed: \(error.localizedDescription, privacy: .public)")
            }
            pendingCorrections -= 1
            await applyCorrection(id, original: source, corrected: corrected)
        }
    }

    private func applyCorrection(_ id: UUID, original: String, corrected: String?) async {
        guard let i = index(of: id) else { return }
        lines[i].correctionPending = false
        guard let corrected, lines[i].source == original else {
            if lines[i].state == .done || lines[i].state == .failed { persist(id) }
            return
        }
        if settings.keepOriginalText { lines[i].originalSource = original }
        lines[i].source = corrected
        // 原文的 Google 译文还没回来也不用等：它回来时发现原文已经换了，会自己作废（`finishLine`）。
        var translation: String?
        if let basic = basicTranslator {
            translation = try? await basic.translate(corrected, context: recentContext(before: id), onPartial: { _ in })
        }
        guard let j = index(of: id) else { return }
        if let translation { lines[j].translation = translation }
        lines[j].state = lines[j].translation.isEmpty ? .failed : .done
        persist(id)
    }
}
