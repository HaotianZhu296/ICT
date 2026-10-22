import AppKit
import ICTCore
import SwiftUI

/// 本次的字幕记录窗口（字幕上的“字幕记录”按钮）：全部字幕，以及笔记、导出、历史记录。
struct HistoryView: View {
    let controller: SubtitleController
    let onShowArchive: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(controller.lines) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(line.time, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let label = line.sourceLabel {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                            }
                            if let note = line.note {
                                Text(note).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Text(line.source).textSelection(.enabled)
                        if let original = line.originalSource, original != line.source {
                            Text(L("识别原文：%@", original)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if !line.translation.isEmpty {
                            Text(line.translation).font(.body.weight(.medium)).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                    .id(line.id)
                }
                .onChange(of: controller.lines.count) {
                    if let last = controller.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text(controller.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("历史记录…", action: onShowArchive)
                if let url = controller.transcriptURL {
                    Button("在 Finder 中显示记录") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Menu("导出字幕") {
                    ForEach(SubtitleFileFormat.allCases, id: \.self) { format in
                        Button(format.menuTitle) { controller.exportSubtitles(format: format) }
                    }
                }
                .fixedSize()
                .disabled(controller.lines.isEmpty)
                Button("开始新的记录") { controller.newSession() }
                    .help("清空本次的字幕，下次开始时写进一份新的记录文件。")
                Button(controller.notesInProgress ? L("正在生成…") : L("生成笔记")) { controller.generateNotes() }
                    .disabled(controller.notesInProgress || controller.lines.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
