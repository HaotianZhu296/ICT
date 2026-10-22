import AppKit
import ICTCore
import SwiftUI

/// 历史记录窗口：列出记录文件夹里的字幕记录（文件名是开始记录的时间），查看内容，并一键总结。
/// 总结存成“时间 总结.md”放在记录旁边，下次打开直接显示。
@MainActor @Observable
final class ArchiveModel {
    struct Item: Identifiable, Hashable {
        let url: URL
        let started: Date
        var id: URL { url }
    }

    private(set) var items: [Item] = []
    var selection: URL? {
        didSet { if selection != oldValue { load() } }
    }
    private(set) var content = ""
    private(set) var summary: String?
    private(set) var summarizing = false
    private(set) var error: String?
    /// 已经有总结的记录（列表里标出来）。
    private(set) var summarized: Set<URL> = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var session: ChatSession?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var folder: URL {
        URL(fileURLWithPath: (settings.transcriptFolder as NSString).expandingTildeInPath, isDirectory: true)
    }

    var summaryModelName: String { settings.displayName(settings.assistantModel) }

    /// 重新扫描记录文件夹，最新的在最上面。
    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        items = names.filter(TranscriptArchive.isTranscript).compactMap { name in
            TranscriptArchive.startDate(of: name).map { Item(url: folder.appendingPathComponent(name), started: $0) }
        }
        .sorted { ($0.started, $0.url.lastPathComponent) > ($1.started, $1.url.lastPathComponent) }
        summarized = Set(items.map(\.url).filter { FileManager.default.fileExists(atPath: summaryURL(for: $0).path) })
        if selection.map({ url in !items.contains { $0.url == url } }) ?? true {
            selection = items.first?.url
        } else {
            load()
        }
    }

    private func summaryURL(for transcript: URL) -> URL {
        TranscriptStore.derivedURL(for: transcript, suffix: L("总结"))
    }

    private func load() {
        error = nil
        guard let url = selection, !summarizing else {
            if selection == nil { content = ""; summary = nil }
            return
        }
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        summary = try? String(contentsOf: summaryURL(for: url), encoding: .utf8)
    }

    /// 用 AI 助手的模型（默认 Claude Sonnet）总结选中的记录，边生成边显示，完成后存文件。
    func summarize() {
        guard let url = selection, !summarizing, !content.isEmpty else { return }
        let session: ChatSession
        do {
            session = try ChatSessionFactory.make(settings.assistantModel, settings: settings,
                                                  systemPrompt: Prompts.summaryPrompt(target: settings.target),
                                                  maxTurns: 1, timeout: 600)
        } catch {
            self.error = error.localizedDescription
            return
        }
        self.session = session
        summarizing = true
        error = nil
        summary = ""
        let transcript = content
        let target = summaryURL(for: url)
        Task {
            defer {
                summarizing = false
                session.shutdown()
                self.session = nil
            }
            do {
                let result = try await session.request(newSessionMessage: transcript, ongoingMessage: transcript) { partial in
                    Task { @MainActor [weak self] in
                        if self?.summarizing == true, self?.selection == url { self?.summary = partial }
                    }
                }
                try result.write(to: target, atomically: true, encoding: .utf8)
                summarized.insert(url)
                if selection == url { summary = result }
            } catch {
                if selection == url {
                    summary = try? String(contentsOf: target, encoding: .utf8)
                    self.error = L("总结失败：%@", error.localizedDescription)
                }
            }
        }
    }
}

struct ArchiveView: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        HStack(spacing: 0) {
            List(model.items, selection: $model.selection) { item in
                HStack {
                    Text(item.started, format: .dateTime.year().month().day().hour().minute())
                    Spacer()
                    if model.summarized.contains(item.url) {
                        Image(systemName: "sparkles").foregroundStyle(.secondary).help(L("已总结"))
                    }
                }
                .tag(item.url)
            }
            .frame(width: 220)
            .overlay {
                if model.items.isEmpty {
                    Text("还没有历史记录").foregroundStyle(.secondary)
                }
            }
            Divider()
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { model.reload() }
    }

    @ViewBuilder
    private var detail: some View {
        if let url = model.selection {
            VStack(spacing: 0) {
                HStack {
                    Text(url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(1)
                    Spacer()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button {
                        model.summarize()
                    } label: {
                        if model.summarizing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("正在总结…")
                            }
                        } else {
                            Label(model.summary == nil ? L("用 %@ 总结", model.summaryModelName) : L("重新总结"),
                                  systemImage: "sparkles")
                        }
                    }
                    .disabled(model.summarizing || model.content.isEmpty)
                }
                .padding(12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        if let summary = model.summary {
                            GroupBox {
                                markdown(summary.isEmpty ? "…" : summary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(4)
                            } label: {
                                Label("总结", systemImage: "sparkles")
                            }
                        }
                        markdown(model.content)
                    }
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Text("选择左边的一份记录").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Markdown 的粗体、斜体等按样式显示，换行原样保留。
    private func markdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
    }
}
