import Foundation

struct QuestionBankAgentSource {
    var id: String
    var text: String
    var questions: [ParsedQuizQuestion] { QuizBulkParser.parse(text) }

    static func extract(_ text: String) -> (request: String, bank: String)? {
        guard let range = text.range(of: "(?m)^QUESTION[ \\t]*$", options: .regularExpression) else { return nil }
        return (String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), String(text[range.lowerBound...]))
    }
    static func authorizesImport(_ request: String) -> Bool {
        let text = request.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let action = ["import", "add", "save", "ajoute", "enregistre"].contains { text.contains($0) }
        let object = ["question", "quiz", "bank", "banque", "practice", "pratique"].contains { text.contains($0) }
        let readOnly = ["do not import", "don't import", "ne pas importer", "n'importe pas", "explain", "summar", "explique", "resume"].contains { text.contains($0) }
        return action && object && !readOnly
    }
}
