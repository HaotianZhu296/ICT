import Foundation
import Testing
@testable import ICTCore

@Suite struct SegmentTimelineTests {
    @Test func timelineSplitsOneFinalIntoTwoSegments() {
        var t = SegmentTimeline()
        t.addFinal("aaaa bbbb", start: 10, end: 18)   // 8 个非空白字符
        let first = t.take("aaaa")
        let second = t.take("bbbb")
        #expect(first?.start == 10 && first?.end == 14)
        #expect(second?.start == 14 && second?.end == 18)
        let none = t.take("more")
        #expect(none == nil)
    }

    @Test func timelineMergesTwoFinalsIntoOneSegment() {
        var t = SegmentTimeline()
        t.addFinal("Okay.", start: 1, end: 2)
        t.addFinal("Let's start.", start: 3, end: 5)
        let merged = t.take("Okay. Let's start.")
        #expect(merged?.start == 1 && merged?.end == 5)
    }
}
