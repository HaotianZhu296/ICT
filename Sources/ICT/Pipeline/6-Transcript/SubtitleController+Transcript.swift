import AppKit
import ICTCore

enum SubtitleFileFormat: String, CaseIterable {
    case srt, vtt
    var menuTitle: String { self == .srt ? "SRT…" : "WebVTT…" }
}

/// 流水线第 6 步：把每句写进记录文件，导出字幕，生成笔记。
extension SubtitleController {
    func openStore() {
        store = TranscriptStore(folderPath: settings.transcriptFolder, started: Date(),
                                source: settings.source, target: settings.target)
    }

    func persist(_ id: UUID) {
        guard let line = lines.first(where: { $0.id == id }) else { return }
        store?.append(TranscriptFormat.entry(time: line.time, sourceLabel: line.sourceLabel,
                                             source: line.source, translation: line.translation,
                                             original: line.originalSource))
    }

    // MARK: - 导出字幕

    /// 字幕文件内容：时间相对这份记录开始录音的时刻；文字按当前“显示内容”（双语/仅译文/仅原文）。
    func subtitleFileContents(format: SubtitleFileFormat) -> String {
        let reference = sessionStart ?? lines.compactMap(\.audioStart).min() ?? lines.first?.time ?? Date()
        let mode = settings.displayMode
        let cues: [SubtitleExport.Cue] = lines.map { line in
            let text: String
            switch mode {
            case .bilingual: text = line.translation.isEmpty ? line.source : "\(line.source)\n\(line.translation)"
            case .translationOnly: text = line.translation.isEmpty ? line.source : line.translation
            case .sourceOnly: text = line.source
            }
            // 没有逐词时间的句子按入队时间往前估 3 秒。
            let start = line.audioStart ?? line.time.addingTimeInterval(-3)
            let end = line.audioEnd ?? line.time
            return SubtitleExport.Cue(start: start.timeIntervalSince(reference), end: end.timeIntervalSince(reference), text: text)
        }
        return format == .srt ? SubtitleExport.srt(cues) : SubtitleExport.vtt(cues)
    }

    func exportSubtitles(format: SubtitleFileFormat) {
        let content = subtitleFileContents(format: format)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (store?.fileURL.deletingPathExtension().lastPathComponent ?? L("ICT 字幕")) + "." + format.rawValue
        panel.directoryURL = store?.fileURL.deletingLastPathComponent()
        FilePanel.present(panel) { [weak self] url in
            guard let self, let url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                status = L("字幕已导出：%@", url.lastPathComponent)
            } catch {
                showAlert(L("导出失败：%@", error.localizedDescription))
            }
        }
    }

    // MARK: - 笔记

    func generateNotes() {
        guard !notesInProgress else { return }
        let done = lines.filter { !$0.source.isEmpty }
        guard !done.isEmpty else {
            status = L("还没有字幕记录，无法生成笔记。")
            return
        }
        // 笔记用 AI 助手的模型。
        let session: ChatSession
        do {
            session = try ChatSessionFactory.make(settings.assistantModel, settings: settings,
                                                  systemPrompt: Prompts.notesPrompt(target: settings.target),
                                                  maxTurns: 1, timeout: 600)
        } catch {
            status = error.localizedDescription
            return
        }
        notesInProgress = true
        status = L("正在用 %@ 生成笔记…", settings.displayName(settings.assistantModel))
        let transcript = TranscriptFormat.plain(done.map { ($0.time, $0.source, $0.translation) })
        let notesURL = store?.notesURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(L("ICT 笔记") + ".md")
        Task {
            defer { notesInProgress = false }
            do {
                let notes = try await session.request(newSessionMessage: transcript, ongoingMessage: transcript,
                                                      onPartial: { _ in })
                session.shutdown()
                try notes.write(to: notesURL, atomically: true, encoding: .utf8)
                status = L("笔记已保存：%@", notesURL.lastPathComponent)
                NSWorkspace.shared.open(notesURL)
            } catch {
                status = L("生成笔记失败：%@", error.localizedDescription)
            }
        }
    }
}
