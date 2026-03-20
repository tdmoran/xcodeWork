import XCTest
@testable import ENTExaminer

final class SentenceSplitterTests: XCTestCase {
    let splitter = SentenceSplitter()

    func testEmptyBuffer() {
        let result = splitter.extract(from: "")
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertEqual(result.remainder, "")
    }

    func testSingleCompleteSentence() {
        let result = splitter.extract(from: "This is a complete sentence. ")
        XCTAssertEqual(result.sentences, ["This is a complete sentence."])
        XCTAssertEqual(result.remainder, "")
    }

    func testIncompleteSentence() {
        let result = splitter.extract(from: "This is not finished yet")
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertEqual(result.remainder, "This is not finished yet")
    }

    func testMultipleSentences() {
        let result = splitter.extract(from: "First sentence here. Second sentence here. Third incomplete")
        XCTAssertEqual(result.sentences.count, 2)
        XCTAssertEqual(result.sentences[0], "First sentence here.")
        XCTAssertEqual(result.sentences[1], "Second sentence here.")
        XCTAssertEqual(result.remainder, "Third incomplete")
    }

    func testExclamationAndQuestionMark() {
        let result = splitter.extract(from: "What is photosynthesis? It converts light to energy! More text")
        XCTAssertEqual(result.sentences.count, 2)
        XCTAssertTrue(result.sentences[0].hasSuffix("?"))
        XCTAssertTrue(result.sentences[1].hasSuffix("!"))
        XCTAssertEqual(result.remainder, "More text")
    }

    func testAbbreviationsNotSplit() {
        let result = splitter.extract(from: "Dr. Smith explained the process. It was clear.")
        XCTAssertEqual(result.sentences.count, 2)
        XCTAssertTrue(result.sentences[0].contains("Dr."))
    }

    func testSentenceAtEndOfString() {
        let result = splitter.extract(from: "This is a complete sentence at the end.")
        XCTAssertEqual(result.sentences, ["This is a complete sentence at the end."])
        XCTAssertEqual(result.remainder, "")
    }

    func testDecimalsNotSplit() {
        let result = splitter.extract(from: "The value is 3.14 approximately. That is pi.")
        XCTAssertEqual(result.sentences.count, 2)
        XCTAssertTrue(result.sentences[0].contains("3.14"))
    }

    func testLongSingleSentence() {
        let long = "This is a very long sentence that goes on and on and contains many words but never actually ends with a period or any other sentence-ending punctuation"
        let result = splitter.extract(from: long)
        XCTAssertTrue(result.sentences.isEmpty)
        XCTAssertEqual(result.remainder, long)
    }
}
