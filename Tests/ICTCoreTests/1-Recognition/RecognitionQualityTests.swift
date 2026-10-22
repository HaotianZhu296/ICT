import Foundation
import Testing
@testable import ICTCore

@Suite struct RecognitionQualityTests {
    @Test func clearSpeechStaysClear() {
        var m = RecognitionQualityMonitor()
        let changed = m.add(Array(repeating: 0.93, count: 30))
        #expect(!changed)
        #expect(!m.isDifficult)
    }

    @Test func accentedSpeechTurnsOnCorrection() {
        var m = RecognitionQualityMonitor()
        let tooFew = m.add(Array(repeating: 0.72, count: 10))  // 词太少，先不判断
        #expect(!tooFew)
        let changed = m.add(Array(repeating: 0.74, count: 15))
        #expect(changed)
        #expect(m.isDifficult)
    }

    @Test func hysteresisAvoidsFlipping() {
        let t0 = Date()
        var m = RecognitionQualityMonitor()
        m.add(Array(repeating: 0.7, count: 60), at: t0)
        #expect(m.isDifficult)
        // 0.83 介于两个阈值之间：保持难识别
        m.add(Array(repeating: 0.83, count: 60), at: t0.addingTimeInterval(5))
        #expect(m.isDifficult)
        // 清楚了，但要连续清楚 60 秒才恢复
        let early = m.add(Array(repeating: 0.92, count: 60), at: t0.addingTimeInterval(10))
        let half = m.add(Array(repeating: 0.92, count: 12), at: t0.addingTimeInterval(40))
        #expect(!early && !half)
        let recovered = m.add(Array(repeating: 0.92, count: 12), at: t0.addingTimeInterval(70))
        #expect(recovered)
        #expect(!m.isDifficult)
    }

    @Test func briefClearSpellKeepsCorrection() {
        // 口音重的讲者中间有二十几秒说得清楚：不要关掉纠正。每 5 秒一句，每句 12 个词。
        let t0 = Date()
        var m = RecognitionQualityMonitor()
        m.add(Array(repeating: 0.72, count: 60), at: t0)
        #expect(m.isDifficult)
        var changes = 0
        func say(_ confidence: Double, at second: Double) {
            if m.add(Array(repeating: confidence, count: 12), at: t0.addingTimeInterval(second)) { changes += 1 }
        }
        for second in stride(from: 5.0, through: 25, by: 5) { say(0.97, at: second) }  // 第 15 秒起平均高于 0.86，开始计时
        say(0.3, at: 30)                                                                // 一句没认准：平均掉下来，重新计时
        for second in stride(from: 35.0, through: 80, by: 5) { say(0.97, at: second) } // 第 55 秒起重新计时
        // 不重新计时的话，第 75 秒（15 + 60）就恢复了
        #expect(changes == 0)
        #expect(m.isDifficult)
        for second in stride(from: 85.0, through: 115, by: 5) { say(0.97, at: second) }
        #expect(changes == 1)
        #expect(!m.isDifficult)
    }

    @Test func oneUnclearSentenceDoesNotStartCorrection() {
        var m = RecognitionQualityMonitor()
        m.add(Array(repeating: 0.92, count: 48))
        let changed = m.add(Array(repeating: 0.55, count: 12))
        #expect(!changed)
        #expect(!m.isDifficult)
    }
}
