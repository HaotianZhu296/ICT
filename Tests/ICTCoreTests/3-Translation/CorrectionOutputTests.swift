import Testing
@testable import ICTCore

@Suite struct CorrectionOutputTests {
    @Test func unchangedReplies() {
        let original = "First we sort the edges by weight."
        #expect(CorrectionOutput.parse("=", original: original) == nil)
        #expect(CorrectionOutput.parse(" =\n", original: original) == nil)
        // 只改了标点、大小写：不值得重新翻译。
        #expect(CorrectionOutput.parse("First, we sort the edges by weight", original: original) == nil)
    }

    @Test func correctedReplies() {
        #expect(CorrectionOutput.parse("Today we talk about the minimum spanning tree.",
                                       original: "Today we talk about the minimum Hispanic tree.")
                == "Today we talk about the minimum spanning tree.")
        // 引号、后面多出来的说明都去掉。
        #expect(CorrectionOutput.parse("\"Python has a nice library for this.\"\n(Chithon → Python)",
                                       original: "Chithon has a nice library for this.")
                == "Python has a nice library for this.")
    }

    @Test func implausibleRepliesAreIgnored() {
        // 回答了问题，而不是纠正：长度差太多。
        #expect(CorrectionOutput.parse("Yes, Kruskal's algorithm always finds a minimum spanning tree because the cut property guarantees every chosen edge is safe.",
                                       original: "Any questions?") == nil)
    }

    @Test func correctionMessageContext() {
        #expect(Prompts.correctionMessage(text: "We call it heap queue.", context: []) == "We call it heap queue.")
        #expect(Prompts.correctionMessage(text: "We call it heap queue.", context: ["Chithon has a nice library."])
                == "[Context]\nChithon has a nice library.\n[Correct]\nWe call it heap queue.")
    }
}
