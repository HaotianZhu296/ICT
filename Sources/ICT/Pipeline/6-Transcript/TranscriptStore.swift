import Foundation
import ICTCore

/// 把每一句原文 + 译文实时追加写入 Markdown 文件，崩溃或断电也不会丢失之前的记录。
final class TranscriptStore {
    let fileURL: URL
    let started: Date

    init(folderPath: String, started: Date, source: LanguageOption, target: LanguageOption) {
        self.started = started
        let stamp = TranscriptFormat.fileStampFormatter.string(from: started)
        let preferred = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ICT/Transcripts", isDirectory: true)

        let header = TranscriptFormat.header(title: "\(stamp) \(L("字幕记录"))", started: started, source: source, target: target)
        var chosen = fallback.appendingPathComponent("\(stamp).md")
        for folder in [preferred, fallback] {
            // 文件名就是开始记录的时间。
            let name = TranscriptArchive.newFileName(started: started) {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
            let url = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try header.write(to: url, atomically: true, encoding: .utf8)
                chosen = url
                break
            } catch {
                continue
            }
        }
        fileURL = chosen
    }

    func append(_ text: String) {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    var notesURL: URL { Self.derivedURL(for: fileURL, suffix: L("笔记")) }

    /// 字幕记录旁边的笔记、总结文件。
    static func derivedURL(for transcript: URL, suffix: String) -> URL {
        transcript.deletingLastPathComponent()
            .appendingPathComponent(TranscriptArchive.derivedName(for: transcript.lastPathComponent, suffix: suffix))
    }
}
