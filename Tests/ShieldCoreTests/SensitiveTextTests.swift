//  Created by Clinton Imaro on 20/09/2026.

import XCTest
@testable import ShieldCore

final class SensitiveTextTests: XCTestCase {
    func testCredentialPatternsFindGeneratedExamples() {
        let examples = ["sk-" + String(repeating: "x", count: 32),
                        "ghp_" + String(repeating: "x", count: 36),
                        "password: demonstration-only", "API_KEY = 'example-only-value'"]
        for text in examples { XCTAssertFalse(SensitiveText.ranges(in: text, options: .credentials).isEmpty) }
        XCTAssertTrue(SensitiveText.ranges(in: "Choose a password with at least 12 characters", options: .credentials).isEmpty)
    }

    func testEmailAndCardDetectionRequireTheirOwnOptions() {
        let text = "Email: sample@example.test"
        XCTAssertTrue(SensitiveText.ranges(in: text, options: .credentials).isEmpty)
        XCTAssertEqual(SensitiveText.ranges(in: text, options: .emailAddresses).count, 1)
        XCTAssertTrue(SensitiveText.ranges(in: text, options: []).isEmpty)
        let card = "4111 1111 1111 1111"
        XCTAssertEqual(SensitiveText.ranges(in: card, options: .paymentCards).count, 1)
        XCTAssertTrue(SensitiveText.ranges(in: card, options: .emailAddresses).isEmpty)
    }

    func testPaymentCardsRequireValidChecksumAndLength() {
        XCTAssertTrue(SensitiveText.isPaymentCard("4111-1111-1111-1111"))
        for invalid in ["4111 1111 1111 1112", "0000000000000000", "123456", "41111111111111111111"] {
            XCTAssertFalse(SensitiveText.isPaymentCard(invalid))
            XCTAssertTrue(SensitiveText.ranges(in: invalid, options: .paymentCards).isEmpty)
        }
    }

    func testMatchesUseValidUnicodeStringRanges() throws {
        let text = "🔒 Contact sample@example.test for help"
        let match = try XCTUnwrap(SensitiveText.ranges(in: text, options: .emailAddresses).first)
        let range = try XCTUnwrap(Range(match, in: text))
        XCTAssertEqual(String(text[range]), "sample@example.test")
    }
}

extension SensitiveTextTests {
    func testCustomPhrasesAreLiteralCaseInsensitiveAndFindRepeatedMatches() {
        let text = "Café [private]. CAFÉ [private]. Other data."
        let matches = SensitiveText.ranges(in: text, options: [], phrases: ["cafe [private]"])
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["Café [private]", "CAFÉ [private]"])
    }

    func testCustomPhrasesRejectEmptyAndDuplicateValues() {
        XCTAssertEqual(SensitiveText.cleanPhrases([" ", "  Private ", "PRIVATE", "café", "CAFE"]), ["Private", "café"])
        XCTAssertEqual(SensitiveText.cleanPhrases((0...70).map { "Phrase \($0)" }).count, 50)
        XCTAssertEqual(SensitiveText.cleanPhrases([String(repeating: "a", count: 250)]).first?.count, 200)
    }
}
