import Foundation
import Testing
@testable import ICTCore

@Suite struct BreathCutterTests {
    /// 按 0.05 秒一块送入音频，返回第一次切分的时间。
    func feed(_ cutter: inout BreathCutter, from: Double, to: Double, level: Float) -> Double? {
        var t = from
        var cut: Double?
        while t < to - 1e-9 {
            t += 0.05
            if let c = cutter.addAudio(level: level, duration: 0.05, end: t), cut == nil { cut = c }
        }
        return cut
    }

    @Test func cutsAtBreathInLongUtterance() {
        var cutter = BreathCutter()
        cutter.updateVolatile(words: 20, start: 0)
        #expect(feed(&cutter, from: 0, to: 5, level: 0.1) == nil)
        let cut = feed(&cutter, from: 5, to: 5.3, level: 0.01)
        #expect(cut.map { abs($0 - 5.075) < 0.01 } == true)
    }

    @Test func ignoresGapsBetweenWords() {
        var cutter = BreathCutter()
        cutter.updateVolatile(words: 20, start: 0)
        _ = feed(&cutter, from: 0, to: 5, level: 0.1)
        // 0.1 秒的字间间隙不算换气。
        #expect(feed(&cutter, from: 5, to: 5.1, level: 0.01) == nil)
        #expect(feed(&cutter, from: 5.1, to: 6, level: 0.1) == nil)
    }

    @Test func waitsForEnoughWordsAndTime() {
        var cutter = BreathCutter()
        cutter.updateVolatile(words: 8, start: 0)
        _ = feed(&cutter, from: 0, to: 5, level: 0.1)
        #expect(feed(&cutter, from: 5, to: 5.5, level: 0.01) == nil)  // 词太少

        var short = BreathCutter()
        short.updateVolatile(words: 20, start: 0)
        _ = feed(&short, from: 0, to: 2, level: 0.1)
        #expect(feed(&short, from: 2, to: 2.5, level: 0.01) == nil)  // 说得还不够久
    }

    @Test func cutsOnceUntilFinalArrives() {
        var cutter = BreathCutter()
        cutter.updateVolatile(words: 20, start: 0)
        _ = feed(&cutter, from: 0, to: 5, level: 0.1)
        #expect(feed(&cutter, from: 5, to: 5.3, level: 0.01) != nil)
        _ = feed(&cutter, from: 5.3, to: 6, level: 0.1)
        #expect(feed(&cutter, from: 6, to: 6.3, level: 0.01) == nil)  // 还在等上一次切分的确认结果

        cutter.finalReceived()
        cutter.updateVolatile(words: 18, start: 5.1)
        _ = feed(&cutter, from: 6.3, to: 10, level: 0.1)
        #expect(feed(&cutter, from: 10, to: 10.3, level: 0.01) != nil)
    }
}
