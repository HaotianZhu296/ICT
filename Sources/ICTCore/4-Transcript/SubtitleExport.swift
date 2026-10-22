import Foundation

/// 导出 SRT / WebVTT 字幕文件。时间是相对录音开始的秒数。
public enum SubtitleExport {
    public struct Cue: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public static func srt(_ cues: [Cue]) -> String {
        tidy(cues).enumerated().map { i, cue in
            "\(i + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    public static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + tidy(cues).map { cue in
            "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// 按时间排序；每条至少显示 1 秒，但不和下一条重叠；去掉空字幕。
    static func tidy(_ cues: [Cue]) -> [Cue] {
        var sorted = cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Cue(start: max(0, $0.start), end: max(0, $0.end), text: $0.text) }
            .sorted { $0.start < $1.start }
        for i in sorted.indices {
            var end = max(sorted[i].end, sorted[i].start + 1)
            if i + 1 < sorted.count { end = min(end, sorted[i + 1].start) }
            sorted[i].end = max(end, sorted[i].start + 0.1)
        }
        return sorted
    }

    static func timestamp(_ seconds: Double, separator: String) -> String {
        let ms = Int((seconds * 1000).rounded())
        let h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60, f = ms % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, f)
    }
}
