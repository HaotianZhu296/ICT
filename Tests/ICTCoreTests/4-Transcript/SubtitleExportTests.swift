import Foundation
import Testing
@testable import ICTCore

@Suite struct SubtitleExportTests {
    @Test func srtAndVttFormatting() {
        let cues = [
            SubtitleExport.Cue(start: 3661.5, end: 3663, text: "第二句"),
            SubtitleExport.Cue(start: 0.25, end: 0.5, text: "第一句\nFirst"),
            SubtitleExport.Cue(start: 5, end: 6, text: "  "),
        ]
        #expect(SubtitleExport.srt(cues) == """
        1
        00:00:00,250 --> 00:00:01,250
        第一句
        First

        2
        01:01:01,500 --> 01:01:03,000
        第二句

        """)
        #expect(SubtitleExport.vtt(cues).hasPrefix("WEBVTT\n\n00:00:00.250 --> 00:00:01.250\n第一句\nFirst\n"))
    }

    @Test func cuesDoNotOverlap() {
        let tidy = SubtitleExport.tidy([
            .init(start: 0, end: 5, text: "a"),
            .init(start: 2, end: 3, text: "b"),
        ])
        #expect(tidy[0].end == 2)
    }
}
