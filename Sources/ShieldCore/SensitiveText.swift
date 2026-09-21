//  Created by Clinton Imaro on 20/09/2026.

import Foundation

public struct SensitiveTextOptions: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let credentials = SensitiveTextOptions(rawValue: 1)
    public static let emailAddresses = SensitiveTextOptions(rawValue: 2)
    public static let paymentCards = SensitiveTextOptions(rawValue: 4)
}

public enum SensitiveText {
    private static let credentialPatterns = [
        #"\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{16,})\b"#,
        #"(?i)\b(?:password|secret|api[_ -]?key|access[_ -]?token)\s*[:=]\s*[\"']?[^\s\"']{6,}"#,
        #"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }
    private static let email = try! NSRegularExpression(pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#)
    private static let card = try! NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#)

    public static func ranges(in text: String, options: SensitiveTextOptions, phrases: [String] = []) -> [NSRange] {
        let entire = NSRange(text.startIndex..<text.endIndex, in: text)
        var ranges: [NSRange] = []
        if options.contains(.credentials) {
            ranges += credentialPatterns.flatMap { $0.matches(in: text, range: entire).map(\.range) }
        }
        if options.contains(.emailAddresses) { ranges += email.matches(in: text, range: entire).map(\.range) }
        if options.contains(.paymentCards) {
            ranges += card.matches(in: text, range: entire).filter { result in
                guard let range = Range(result.range, in: text) else { return false }
                return isPaymentCard(String(text[range]))
            }.map(\.range)
        }
        for phrase in cleanPhrases(phrases) {
            var search = text.startIndex..<text.endIndex
            while let match = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
                ranges.append(NSRange(match, in: text))
                search = match.upperBound..<text.endIndex
            }
        }
        return ranges
    }

    public static func cleanPhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        return Array(phrases.compactMap { value -> String? in
            let phrase = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            guard !phrase.isEmpty, seen.insert(phrase.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)).inserted else { return nil }
            return phrase
        }.prefix(50))
    }

    public static func isPaymentCard(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, entry in
            let value = entry.offset % 2 == 1 ? entry.element * 2 : entry.element
            return total + (value > 9 ? value - 9 : value)
        }
        return sum % 10 == 0
    }
}
