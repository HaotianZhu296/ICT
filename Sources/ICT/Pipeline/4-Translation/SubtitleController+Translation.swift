import AppKit
import ICTCore

/// 流水线第 4 步：准备翻译器、翻译队列（积压合并、Google/Apple 并行、出错时的备用翻译）。
extension SubtitleController {
    func resetTranslators() {
        retire(translator)
        if basicTranslator !== translator { retire(basicTranslator) }
        translator = nil
        basicTranslator = nil
        fallback = nil
        usingFallback = false
        translatorPending = true
    }

    /// 旧翻译器过一会儿再关：正在翻译的那句还要用它，立刻关会让那一句翻译失败。
    func retire(_ old: Translator?) {
        guard let old else { return }
        Task {
            try? await Task.sleep(for: .seconds(30))
            old.shutdown()
        }
    }

    // MARK: - 翻译器

    func prepareTranslators() async {
        defer { translatorPending = false }
        // 上次 Claude 不可用（例如未登录）的话，每次“开始”都重新试一次：用户可能已经登录了。
        if usingFallback {
            translator?.shutdown()
            translator = nil
            usingFallback = false
            ClaudeCLI.reloadShellEnvironment()
        }
        let source = settings.source, target = settings.target
        // Apple 本地翻译（所选模型出错时的备用翻译）需要 macOS 26。
        fallback = nil
        if #available(macOS 26, *), source.translationCode != target.translationCode,
           await AppleTranslator.isInstalled(source: source, target: target) {
            fallback = AppleTranslator(source: source, target: target)
        }

        guard translator == nil else { return }
        claudeAvailable = ClaudeCLI.locate(customPath: settings.claudePath) != nil
        if !settings.translationModel.isLanguageModel {
            prepareBasicTranslator(source: source, target: target)
            // 改设置时正处在识别困难中：直接用带纠正的会话。
            if correcting, let model = correctionModel, let session = try? makeModelSession(model) {
                translator = session
            }
            return
        }
        do {
            translator = try makeModelSession(settings.translationModel)
        } catch {
            // 所选模型用不了（没装 Claude Code、服务被删除）：先用 Apple 本地翻译顶上。
            translator = fallback
            usingFallback = fallback != nil
            status = error.localizedDescription
            showAlert(error.localizedDescription)
        }
    }

    /// Google 翻译或 Apple 本地翻译。
    func prepareBasicTranslator(source: LanguageOption, target: LanguageOption) {
        if settings.translationModel == .google {
            let google = GoogleTranslator(source: source, target: target)
            google.warmUp()
            basicTranslator = google
        } else if #available(macOS 26, *) {
            basicTranslator = fallback ?? AppleTranslator(source: source, target: target)
            // 语言包没下载时每句都会翻译失败：提示并弹出下载窗口，下载完成后设置窗口会重建翻译器。
            if fallback == nil, source.translationCode != target.translationCode {
                showAlert(L("尚未下载“%@ → %@”语言包", L(source.displayName), L(target.displayName)))
                onAppleLanguagesMissing?()
            }
        } else {
            status = L("Apple 本地翻译需要 macOS 26 或更新版本，请选择其他翻译模型。")
            showAlert(status)
        }
        translator = basicTranslator
        translatorBuiltDifficult = false
    }

    /// 按发音纠正用的大模型：所选翻译模型是大模型就用它；Google、Apple 不能纠正，本机有 Claude Code 时
    /// 临时换成 Claude Sonnet。实测（2026-10-22）带上下文时 Sonnet 和 Haiku 一样快，但 Haiku 会编造原文没有的词。
    var correctionModel: ModelChoice? {
        if settings.translationModel.isLanguageModel { return settings.translationModel }
        return claudeAvailable ? .claudeCode("sonnet") : nil
    }

    /// 大模型翻译会话；提示词里带不带“按发音纠正”看当前是否识别困难。
    func makeModelSession(_ model: ModelChoice) throws -> ChatSession {
        let session = try ChatSessionFactory.make(
            model, settings: settings,
            systemPrompt: Prompts.translatorSystemPrompt(source: settings.source, target: settings.target,
                                                         correctMishearings: correcting),
            maxTurns: 40, historyTurns: 12, timeout: 25)
        session.warmUp()
        translatorBuiltDifficult = correcting
        return session
    }

    // MARK: - 翻译队列

    func enqueue(_ segments: [String], from pipeline: SourcePipeline) {
        for text in segments {
            var line = SubtitleLine(time: Date(), sourceLabel: pipeline.label, source: text)
            if let t = pipeline.timeline.take(text) {
                line.audioStart = pipeline.captureStart.addingTimeInterval(t.start)
                line.audioEnd = pipeline.captureStart.addingTimeInterval(t.end)
            }
            lines.append(line)
            queue.append(line.id)
        }
        backlog = queue.count
        if !segments.isEmpty { runWorker() }
    }

    /// Google、Apple 每句独立翻译，同时翻两句，后一句不用等前一句（2026-10-22 实测排队要多等 1 秒多）；
    /// 不多于两句，免得一下子发太多请求被 Google 限流。大模型会话带着上下文，要按顺序一句一句来。
    func runWorker() {
        let limit = basicTranslator != nil && translator === basicTranslator ? 2 : 1
        while activeTranslations < limit, let id = dequeueMerged() {
            activeTranslations += 1
            Task {
                await translateLine(id)
                activeTranslations -= 1
                runWorker()
            }
        }
    }

    /// 取出下一句。如果积压了 2 句以上（翻译跟不上语速），把同一音源的积压句合并成一句一起翻译，
    /// 让字幕延迟不会越积越长。
    func dequeueMerged() -> UUID? {
        guard !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        backlog = queue.count
        guard queue.count >= 2, let firstIndex = index(of: first) else { return first }
        let label = lines[firstIndex].sourceLabel
        var merged: [UUID] = []
        for id in queue {
            guard let i = index(of: id), lines[i].sourceLabel == label,
                  Segmenter.units(lines[firstIndex].source) + Segmenter.units(lines[i].source) <= 70
            else { break }
            lines[firstIndex].source = Segmenter.join(lines[firstIndex].source, lines[i].source)
            if let end = lines[i].audioEnd { lines[firstIndex].audioEnd = end }
            merged.append(id)
        }
        queue.removeAll { merged.contains($0) }
        lines.removeAll { merged.contains($0.id) }
        backlog = queue.count
        return first
    }

    func translateLine(_ id: UUID) async {
        guard let i = index(of: id) else { return }
        let source = lines[i].source
        lines[i].state = .translating
        lines[i].translateStartedAt = Date()
        let context = recentContext(before: id)

        if settings.source.translationCode == settings.target.translationCode {
            finishLine(id, translation: "", note: nil)
            return
        }

        // 换翻译器（改了设置、重新开始）时，新的准备好之前先等一会儿，不要直接判翻译失败。
        let deadline = Date().addingTimeInterval(5)
        while translator == nil, translatorPending, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let primary = usingFallback ? nil : translator
        if let primary {
            do {
                let cjk = settings.targetIsCJK
                let result = try await primary.translate(source, context: context) { [weak self] partial in
                    let visible = TranslationOutput.visibleTranslation(partial, targetIsCJK: cjk)
                    Task { @MainActor in self?.updatePartial(id, visible) }
                }
                let output = TranslationOutput.split(result, original: source, targetIsCJK: cjk)
                finishLine(id, translation: output.translation, note: nil, correctedSource: output.correctedSource)
                return
            } catch {
                let err = error as? TranslatorError
                if err?.isPersistent == true { usingFallback = true }
                status = error.localizedDescription
                showAlert(error.localizedDescription)
                appLog.error("translate failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // 纠正用的 Claude 出错时先用原来的 Google / Apple 翻译这一句。
        if let basic = basicTranslator, basic !== primary {
            do {
                let result = try await basic.translate(source, context: context, onPartial: { _ in })
                finishLine(id, translation: result, note: nil)
                return
            } catch {
                appLog.error("basic translate failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let fallback, fallback !== primary, fallback !== basicTranslator {
            do {
                let result = try await fallback.translate(source, context: context, onPartial: { _ in })
                finishLine(id, translation: result, note: L("Apple 备用"))
                return
            } catch {
                appLog.error("fallback translate failed: \(error.localizedDescription, privacy: .public)")
            }
        } else if primary == nil, basicTranslator == nil {
            appLog.error("translate failed: no translator available")
        }
        if let j = index(of: id) { lines[j].state = .failed }
        persist(id)
    }

    func updatePartial(_ id: UUID, _ partial: String) {
        if let i = index(of: id), lines[i].firstTokenAt == nil, !partial.isEmpty { lines[i].firstTokenAt = Date() }
        guard let i = index(of: id), lines[i].state == .translating,
              partial.count >= lines[i].translation.count else { return }
        lines[i].translation = partial
    }

    func finishLine(_ id: UUID, translation: String, note: String?, correctedSource: String? = nil) {
        guard let i = index(of: id) else { return }
        if ProcessInfo.processInfo.environment["ICT_DEBUG_LATENCY"] != nil {
            let l = lines[i], now = Date()
            func gap(_ a: Date?, _ b: Date?) -> String {
                guard let a, let b else { return "  -  " }
                return String(format: "%5.2f", b.timeIntervalSince(a))
            }
            FileHandle.standardError.write(Data(("[latency] 说完→入队 \(gap(l.audioEnd, l.time))  入队→开始 \(gap(l.time, l.translateStartedAt))"
                + "  开始→首字 \(gap(l.translateStartedAt, l.firstTokenAt))  首字→完成 \(gap(l.firstTokenAt, now))"
                + "  总计 \(gap(l.audioEnd, now))  | \(l.source.prefix(50))\n").utf8))
        }
        // Claude 纠正了识别错误（口音、近音词）时，字幕和记录里都换成纠正后的原文。
        if let correctedSource {
            if settings.keepOriginalText { lines[i].originalSource = lines[i].source }
            lines[i].source = correctedSource
        }
        lines[i].translation = translation
        lines[i].state = .done
        lines[i].note = note
        persist(id)
    }

    func recentContext(before id: UUID) -> ContextPairs {
        guard let i = index(of: id) else { return [] }
        return lines[..<i].filter { $0.state == .done }.suffix(6).map { ($0.source, $0.translation) }
    }

    func index(of id: UUID) -> Int? {
        // 新句子总在末尾，从后往前找更快。
        lines.lastIndex { $0.id == id }
    }
}
