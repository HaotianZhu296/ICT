import AppKit
import ICTCore

/// 流水线第 2、3 步：处理识别结果、分句，判断识别是否困难（决定要不要按发音纠正）。
extension SubtitleController {
    // MARK: - 识别事件

    func handle(_ event: TranscriptEvent, from pipeline: SourcePipeline) {
        switch event {
        case .volatile(let text):
            pipeline.volatileText = text
            pipeline.finalizeRequested = false
        case .final(let result):
            if lines.isEmpty { appLog.notice("first final result") }
            pipeline.volatileText = ""
            pipeline.finalizeRequested = false
            if let start = result.start, let end = result.end {
                pipeline.timeline.addFinal(result.text, start: start, end: end)
            }
            updateQuality(result.confidences)
            enqueue(pipeline.segmenter.addFinal(result.text), from: pipeline)
            // 长句在换气处切出来的前半句：不等后文，直接送去翻译。
            if result.endsClause { enqueue(pipeline.segmenter.flushAll(), from: pipeline) }
        case .filtered:
            pipeline.volatileText = ""
            filteredCount += 1
            status = L("%@ · 已过滤中文说话 %d 段", listeningStatus, filteredCount)
        }
        updateLive(for: pipeline)
    }

    func tick() {
        updateInputStatus()
        if alert != nil, Date().timeIntervalSince(alertAt) > 10 { alert = nil }
        for p in pipelines {
            // 声音停了（1.2 秒没收到音频）但还有没确认的半句：让识别器立即确认，好送去翻译。
            if !p.volatileText.isEmpty, !p.finalizeRequested, p.engine.inputStatus.silentFor > 1.2 {
                p.finalizeRequested = true
                let engine = p.engine
                Task { await engine.finalizePending() }
            }
            let segments = p.segmenter.tick(speechInProgress: !p.volatileText.isEmpty)
            if !segments.isEmpty {
                enqueue(segments, from: p)
                updateLive(for: p)
            }
        }
    }

    func updateLive(for pipeline: SourcePipeline) {
        let key = pipeline.label ?? ""
        let text = pipeline.liveSource.isEmpty ? nil : pipeline.liveSource
        if live[key] != text { live[key] = text }
    }

    // MARK: - 识别质量（自动判断是否需要按发音纠正）

    /// 翻译时是否按发音纠正识别错误：打开了“自动纠正口音”、最近识别困难，并且有能纠正的大模型。
    var correcting: Bool { settings.autoCorrect && recognitionDifficult && correctionModel != nil }

    func updateQuality(_ confidences: [Double]) {
        guard quality.add(confidences) else { return }
        recognitionDifficult = quality.isDifficult
        let average = quality.averageConfidence.map { String(format: "%.2f", $0) } ?? "-"
        appLog.notice("recognition \(self.recognitionDifficult ? "difficult" : "clear", privacy: .public) (avg confidence \(average, privacy: .public))")
        // 没打开自动纠正时只在状态条上提示，不换翻译进程。
        guard settings.autoCorrect, let model = correctionModel, !usingFallback, translator != nil else { return }
        // Google、Apple：识别清楚了换回原来的翻译器（它一直留着，不关）。
        if let basic = basicTranslator, !correcting {
            if translator !== basic { retire(translator) }
            translator = basic
            translatorBuiltDifficult = false
            return
        }
        // 换一个带/不带“按发音纠正”的翻译进程：新的建好后立刻替换，中间不留空档。
        // 以前先置空再异步准备，触发切换的这句（马上就要翻译）正好碰上没有翻译器，每次切换都有一句“翻译失败”。
        // 新进程冷启动只比热进程慢不到 1 秒，所以不等它准备好。旧进程等正在翻译的句子完成后再关。
        do {
            let fresh = try makeModelSession(model)
            if translator !== basicTranslator { retire(translator) }
            translator = fresh
        } catch {
            appLog.error("rebuild translator failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
