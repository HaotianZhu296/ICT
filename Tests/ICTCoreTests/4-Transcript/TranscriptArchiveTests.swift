import Foundation
import Testing
@testable import ICTCore

@Suite struct TranscriptArchiveTests {
    @Test func recognizesTranscriptsOldAndNew() {
        #expect(TranscriptArchive.isTranscript("2026-10-22 13.35.md"))
        #expect(TranscriptArchive.isTranscript("2026-10-22 13.35 (2).md"))
        #expect(TranscriptArchive.isTranscript("2026-10-22 12.35 Transcript.md"))
        #expect(TranscriptArchive.isTranscript("2026-10-22 12.35 字幕记录.md"))
    }

    @Test func skipsDerivedAndOtherFiles() {
        #expect(!TranscriptArchive.isTranscript("2026-10-22 13.35 总结.md"))
        #expect(!TranscriptArchive.isTranscript("2026-10-22 13.35 Summary.md"))
        #expect(!TranscriptArchive.isTranscript("2026-10-22 13.35 笔记.md"))
        #expect(!TranscriptArchive.isTranscript("notes.md"))
        #expect(!TranscriptArchive.isTranscript("2026-10-22 13.35.txt"))
    }

    @Test func derivedNameDropsOldSuffix() {
        #expect(TranscriptArchive.derivedName(for: "2026-10-22 13.35.md", suffix: "总结") == "2026-10-22 13.35 总结.md")
        #expect(TranscriptArchive.derivedName(for: "2026-10-22 12.35 Transcript.md", suffix: "Summary") == "2026-10-22 12.35 Summary.md")
        #expect(TranscriptArchive.derivedName(for: "2026-10-22 12.35 字幕记录.md", suffix: "笔记") == "2026-10-22 12.35 笔记.md")
    }

    @Test func newFileNameAvoidsCollisions() {
        let started = TranscriptFormat.fileStampFormatter.date(from: "2026-10-22 13.35")!
        #expect(TranscriptArchive.newFileName(started: started) { _ in false } == "2026-10-22 13.35.md")
        let taken: Set = ["2026-10-22 13.35.md", "2026-10-22 13.35 (2).md"]
        #expect(TranscriptArchive.newFileName(started: started) { taken.contains($0) } == "2026-10-22 13.35 (3).md")
    }

    @Test func startDateFromName() {
        let date = TranscriptArchive.startDate(of: "2026-10-22 13.35 Transcript.md")
        #expect(date.map { TranscriptFormat.fileStampFormatter.string(from: $0) } == "2026-10-22 13.35")
    }

    @Test func summaryPromptNamesTargetLanguage() {
        #expect(Prompts.summaryPrompt(target: LanguageOption.target("zh-Hans")).contains("Simplified Chinese"))
    }
}
