import Foundation

/// 记录文件夹里的历史记录：字幕记录用开始记录的时间命名（“2026-10-22 13.35.md”），
/// 笔记和总结在后面加后缀放在旁边。以前的版本在时间后面还带“字幕记录”或“Transcript”，同样算字幕记录。
public enum TranscriptArchive {
    /// 字幕记录派生出来的文件（中英文界面各一套后缀）。
    public static let derivedSuffixes = ["笔记", "总结", "Notes", "Summary"]

    /// 这个文件名是不是一份字幕记录。
    public static func isTranscript(_ fileName: String) -> Bool {
        guard fileName.hasSuffix(".md"), startDate(of: fileName) != nil else { return false }
        let base = String(fileName.dropLast(3))
        return !derivedSuffixes.contains { base.hasSuffix(" " + $0) }
    }

    /// 文件名开头的记录开始时间。
    public static func startDate(of fileName: String) -> Date? {
        guard fileName.count >= 16 else { return nil }
        return TranscriptFormat.fileStampFormatter.date(from: String(fileName.prefix(16)))
    }

    /// 和字幕记录放在一起的派生文件名，例如“2026-10-22 13.35 总结.md”。
    public static func derivedName(for transcriptName: String, suffix: String) -> String {
        var base = transcriptName.hasSuffix(".md") ? String(transcriptName.dropLast(3)) : transcriptName
        // 旧文件名带“字幕记录”“Transcript”：总结名只用时间。
        for old in [" 字幕记录", " Transcript"] where base.hasSuffix(old) { base = String(base.dropLast(old.count)) }
        return "\(base) \(suffix).md"
    }

    /// 新记录的文件名：开始时间；同一分钟里已经有了就加序号。
    public static func newFileName(started: Date, exists: (String) -> Bool) -> String {
        let stamp = TranscriptFormat.fileStampFormatter.string(from: started)
        var name = "\(stamp).md"
        var n = 2
        while exists(name) {
            name = "\(stamp) (\(n)).md"
            n += 1
        }
        return name
    }
}
