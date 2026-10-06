import Foundation

struct ParsedFlashcard: Identifiable, Equatable {
    let id = UUID()
    var sourceLine: Int
    var front: String
    var back: String
    var hint: String?
    var explanation: String?
    var tags: [String]
    var warnings: [String] = []
    var errors: [String] = []

    var isValid: Bool { errors.isEmpty && !front.trimmedForStudy.isEmpty && !back.trimmedForStudy.isEmpty }
}

struct FlashcardBulkParseResult {
    var cards: [ParsedFlashcard]
    var duplicateFronts: Set<String>
}

enum FlashcardBulkParser {
    static func parse(_ text: String) -> FlashcardBulkParseResult {
        let blocks = splitBlocks(text)
        var cards: [ParsedFlashcard] = []

        for block in blocks {
            let fields = parseFields(block.text)
            var card = ParsedFlashcard(
                sourceLine: block.line,
                front: fields["front"] ?? "",
                back: fields["back"] ?? "",
                hint: fields["hint"],
                explanation: fields["explanation"],
                tags: splitTags(fields["tags"] ?? "")
            )
            if card.front.trimmedForStudy.isEmpty { card.errors.append("Front is required.") }
            if card.back.trimmedForStudy.isEmpty { card.errors.append("Back is required.") }
            if fields["flashcard"] != nil {
                card.warnings.append("Ignored FLASHCARD marker.")
            }
            cards.append(card)
        }

        let fronts = Dictionary(grouping: cards.map { $0.front.normalizedStudyKey }, by: { $0 })
        let duplicates = Set(fronts.filter { !$0.key.isEmpty && $0.value.count > 1 }.keys)
        return FlashcardBulkParseResult(cards: cards, duplicateFronts: duplicates)
    }

    private static func splitBlocks(_ text: String) -> [(line: Int, text: String)] {
        var blocks: [(line: Int, text: String)] = []
        var current: [String] = []
        var currentStart = 1

        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    blocks.append((currentStart, block))
                }
                current.removeAll()
                currentStart = index + 2
            } else {
                if current.isEmpty {
                    currentStart = index + 1
                }
                current.append(line)
            }
        }

        let final = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty {
            blocks.append((currentStart, final))
        }
        return blocks
    }

    private static func parseFields(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        var currentKey: String?

        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.caseInsensitiveCompare("FLASHCARD") == .orderedSame {
                continue
            }
            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).lowercased().trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                fields[key] = value
                currentKey = key
            } else if let currentKey, !line.isEmpty {
                fields[currentKey, default: ""] += "\n\(line)"
            }
        }
        return fields
    }
}

struct ParsedQuizQuestion: Identifiable, Equatable {
    let id = UUID()
    var sourceLine: Int = 1
    var type: QuizQuestionType
    var prompt: String
    var choices: [String]
    var correctAnswers: [String]
    var explanation: String
    var hint: String?
    var tags: [String]
    var errors: [String] = []

    var isValid: Bool { errors.isEmpty }
}

enum QuizBulkParser {
    static func parse(_ text: String) -> [ParsedQuizQuestion] {
        text.components(separatedBy: "\n---")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(parseBlock)
    }

    nonisolated private static func parseBlock(_ block: String) -> ParsedQuizQuestion {
        let fields = parseFields(block)
        let type = parseType(fields["type"] ?? "multiple choice")
        let choices = ["a", "b", "c", "d", "e", "f"].compactMap { label in
            fields[label].map { "\(label.uppercased()): \($0)" }
        }
        var question = ParsedQuizQuestion(
            type: type,
            prompt: fields["prompt"] ?? "",
            choices: type == .trueFalse ? ["True", "False"] : choices,
            correctAnswers: splitTags(fields["correct"] ?? fields["correctanswer"] ?? ""),
            explanation: fields["explanation"] ?? "",
            hint: fields["hint"],
            tags: splitTags(fields["tags"] ?? "")
        )
        if question.prompt.trimmedForStudy.isEmpty { question.errors.append("Prompt is required.") }
        if question.correctAnswers.isEmpty { question.errors.append("Correct answer is required.") }
        if [.multipleChoice, .multipleSelect].contains(question.type) && question.choices.count < 2 {
            question.errors.append("At least two choices are required.")
        }
        return question
    }

    nonisolated private static func parseFields(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.caseInsensitiveCompare("QUESTION") != .orderedSame,
                  let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).lowercased().replacingOccurrences(of: " ", with: "")
            fields[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    nonisolated private static func parseType(_ value: String) -> QuizQuestionType {
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "")
        if normalized.contains("select") { return .multipleSelect }
        if normalized.contains("true") || normalized.contains("false") { return .trueFalse }
        if normalized.contains("short") { return .shortAnswer }
        return .multipleChoice
    }
}

enum QuizScoringService {
    static func score(questions: [QuizQuestion], answers: [String]) -> (score: Double, maximum: Double) {
        var score = 0.0
        var maximum = 0.0
        for (index, question) in questions.sorted(by: { $0.position < $1.position }).enumerated() {
            let answer = answers.indices.contains(index) ? answers[index].normalizedStudyKey : ""
            let correct = Set(question.correctAnswers.map(\.normalizedStudyKey))
            let submitted = Set(answer.split(separator: ",").map { String($0).normalizedStudyKey })
            maximum += Double(question.points)
            if !answer.isEmpty && (correct.contains(answer) || (!submitted.isEmpty && submitted == correct)) {
                score += Double(question.points)
            }
        }
        return (score, maximum)
    }
}

nonisolated private func splitTags(_ value: String) -> [String] {
    value.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private extension String {
    nonisolated var trimmedForStudy: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var normalizedStudyKey: String {
        trimmedForStudy.lowercased()
    }
}
