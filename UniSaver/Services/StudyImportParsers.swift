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

struct ParsedQuizQuestion: Identifiable, Equatable, Codable {
    var id = UUID()
    var sourceLine: Int = 1
    var type: QuizQuestionType
    var prompt: String
    var choices: [String]
    var correctAnswers: [String]
    var explanation: String
    var hint: String?
    var tags: [String]
    var points: Int? = nil
    var rubric: String? = nil
    var sourceErrors: [String] = []
    var errors: [String] = []

    var isValid: Bool { errors.isEmpty }
}

enum QuizBulkParser {
    static func parse(_ text: String) -> [ParsedQuizQuestion] {
        var blocks: [(Int, String)] = []
        var lines: [String] = []
        var start = 1
        for (offset, line) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if !lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append((start, lines.joined(separator: "\n")))
                }
                lines = []; start = offset + 2
            } else { lines.append(line) }
        }
        if !lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append((start, lines.joined(separator: "\n")))
        }
        return blocks.map { line, block in parseBlock(block, line: line) }
    }

    private static func parseBlock(_ block: String, line: Int) -> ParsedQuizQuestion {
        var fields: [String: String] = [:]
        var current: String?
        var errors: [String] = []
        let keys: Set<String> = ["type", "prompt", "correct", "correctanswer", "explanation", "hint", "tags", "points", "marks", "rubric"]
        for raw in block.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "QUESTION" { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].lowercased().replacingOccurrences(of: " ", with: "")
                let isOption = key.count == 1 && key.first.map { $0 >= "a" && $0 <= "z" } == true
                if keys.contains(key) || isOption {
                    if fields[key] != nil { errors.append("Repeated field \(key).") }
                    fields[key] = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    current = key
                    continue
                }
            }
            if let current { fields[current, default: ""] += "\n" + raw }
            else if !trimmed.isEmpty { errors.append("Unrecognized content before the first field: \(trimmed)") }
        }
        let typeText = (fields["type"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        let types: [String: QuizQuestionType] = ["multiplechoice": .multipleChoice, "multipleselect": .multipleSelect,
            "true/false": .trueFalse, "truefalse": .trueFalse, "shortanswer": .shortAnswer]
        let type = types[typeText] ?? .shortAnswer
        if types[typeText] == nil { errors.append("Unsupported or missing Type: \(fields["type"] ?? "(missing)").") }
        let choices = (65...90).compactMap { code -> String? in
            let letter = String(UnicodeScalar(code)!)
            return fields[letter.lowercased()].map { letter + ": " + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let answer = (fields["correct"] ?? fields["correctanswer"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var question = ParsedQuizQuestion(sourceLine: line, type: type,
            prompt: (fields["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            choices: type == .trueFalse && choices.isEmpty ? ["True", "False"] : choices,
            correctAnswers: type == .shortAnswer ? (answer.isEmpty ? [] : [answer]) : splitTags(answer),
            explanation: (fields["explanation"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            hint: fields["hint"], tags: splitTags(fields["tags"] ?? ""), sourceErrors: errors, errors: errors)
        if let supplied = fields["points"] ?? fields["marks"] {
            if let points = Int(supplied), points > 0 { question.points = points }
            else { question.errors.append("Marks must be a positive whole number.") }
        }
        question.rubric = fields["rubric"]
        question.errors += validationErrors(question)
        return question
    }

    static func validationErrors(_ question: ParsedQuizQuestion) -> [String] {
        var errors: [String] = []
        if question.prompt.trimmedForStudy.isEmpty { errors.append("Prompt is required.") }
        if question.correctAnswers.isEmpty || question.correctAnswers.allSatisfy({ $0.trimmedForStudy.isEmpty }) { errors.append("Correct answer is required.") }
        if question.explanation.trimmedForStudy.isEmpty { errors.append("Explanation is required.") }
        if [.multipleChoice, .multipleSelect].contains(question.type) {
            if question.choices.count < 2 { errors.append("At least two choices are required.") }
            let labels = Set(question.choices.map { QuizScoringService.optionKey($0) })
            if labels.count != question.choices.count { errors.append("Option labels must be unique.") }
            if question.correctAnswers.contains(where: { !labels.contains($0.uppercased()) }) { errors.append("Correct letters must refer to existing options.") }
            if question.type == .multipleChoice && question.correctAnswers.count != 1 { errors.append("Multiple Choice needs exactly one correct option.") }
        }
        if question.type == .trueFalse && (question.correctAnswers.count != 1 || !["true", "false"].contains(question.correctAnswers.first?.lowercased() ?? "")) {
            errors.append("True/False needs Correct: True or Correct: False.")
        }
        return errors
    }
}

enum QuizScoringService {
    static func optionKey(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) == 1 {
            return String(text[..<colon]).uppercased()
        }
        return text
    }

    static func keyError(question: QuizQuestion) -> String? {
        let keys = question.correctAnswers.map { optionKey($0).uppercased() }
        guard !keys.isEmpty, keys.allSatisfy({ !$0.isEmpty }) else { return "Missing answer key." }
        switch question.type {
        case .multipleChoice, .multipleSelect:
            let options = question.choices.map { optionKey($0).uppercased() }
            guard options.count >= 2, Set(options).count == options.count,
                  options.allSatisfy({ $0.count == 1 && $0.first!.isLetter }),
                  keys.allSatisfy({ options.contains($0) }), Set(keys).count == keys.count,
                  question.type != .multipleChoice || keys.count == 1 else { return "Invalid option identifiers or answer key." }
        case .trueFalse:
            guard keys.count == 1, ["TRUE", "FALSE"].contains(keys[0]) else { return "Invalid Boolean answer key." }
        case .shortAnswer: break
        }
        return nil
    }

    static func displayAnswer(question: QuizQuestion, answer: String) -> String {
        guard [.multipleChoice, .multipleSelect].contains(question.type) else { return answer }
        return answer.split(separator: ",").map { value in
            let key = optionKey(String(value)).uppercased()
            return question.choices.first { optionKey($0).uppercased() == key } ?? key
        }.joined(separator: "\n")
    }

    static func selectionDetails(question: QuizQuestion, answer: String) -> String {
        guard question.type == .multipleSelect else { return "" }
        let expected = Set(question.correctAnswers.map { optionKey($0).uppercased() })
        let selected = Set(answer.split(separator: ",").map { optionKey(String($0)).uppercased() })
        let missing = expected.subtracting(selected).sorted()
        let extra = selected.subtracting(expected).sorted()
        return [missing.isEmpty ? nil : "Missing selections: " + missing.joined(separator: ", "),
                extra.isEmpty ? nil : "Extra selections: " + extra.joined(separator: ", ")].compactMap { $0 }.joined(separator: "\n")
    }

    static func inputError(question: QuizQuestion, answer: String) -> String? {
        guard question.type == .shortAnswer, let expected = question.correctAnswers.first,
              decimal(expected) != nil else { return nil }
        if answer.contains(",") { return "Use a decimal point and no comma separators; commas can mean different values." }
        if decimal(answer) == nil { return "Enter a number, with a minus sign or decimal point if needed, and no units." }
        return nil
    }

    static func isCorrect(question: QuizQuestion, answer: String) -> Bool {
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, keyError(question: question) == nil else { return false }
        switch question.type {
        case .multipleSelect:
            let correct = Set(question.correctAnswers.map { optionKey($0).uppercased() })
            let submitted = Set(answer.components(separatedBy: ",").map { optionKey($0).uppercased() })
            return !correct.isEmpty && submitted == correct
        case .multipleChoice:
            let key = optionKey(answer).uppercased()
            return question.correctAnswers.contains { optionKey($0).uppercased() == key }
        case .trueFalse:
            return question.correctAnswers.contains { $0.normalizedStudyKey == answer.normalizedStudyKey }
        case .shortAnswer:
            guard let expected = question.correctAnswers.first else { return false }
            if let number = decimal(expected) {
                guard var actual = decimal(answer), inputError(question: question, answer: answer) == nil else { return false }
                var target = number
                if let places = decimalPlaces(in: question.prompt) {
                    var roundedActual = Decimal(), roundedTarget = Decimal()
                    NSDecimalRound(&roundedActual, &actual, places, .plain)
                    NSDecimalRound(&roundedTarget, &target, places, .plain)
                    return roundedActual == roundedTarget
                }
                return actual == target
            }
            return question.correctAnswers.contains { $0.normalizedStudyKey == answer.normalizedStudyKey }
        }
    }

    static func decimal(_ value: String) -> Decimal? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func decimalPlaces(in prompt: String) -> Int? {
        let pattern = "(?i)(?:round(?:ed)?(?:[^.\\n]{0,35})?(?:to|at)|to)\\s+(\\d+)\\s+decimal\\s+places?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt), let places = Int(prompt[range]), (0...12).contains(places) else {
            return prompt.lowercased().contains("nearest integer") || prompt.lowercased().contains("nearest whole number") || prompt.lowercased().contains("nearest whole euro") ? 0 : nil
        }
        return places
    }

    static func score(questions: [QuizQuestion], answers: [String]) -> (score: Double, maximum: Double) {
        var total = 0.0
        for (index, question) in questions.sorted(by: { $0.position < $1.position }).enumerated() {
            if answers.indices.contains(index) && isCorrect(question: question, answer: answers[index]) { total += Double(question.points) }
        }
        return (total, Double(questions.filter { keyError(question: $0) == nil }.reduce(0) { $0 + $1.points }))
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
