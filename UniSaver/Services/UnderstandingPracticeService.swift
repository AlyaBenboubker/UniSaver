import Foundation
import Security

struct UnderstandingAssistance {
    let hint: String
    let explanationSteps: [String]
    let solution: String
    let transferQuestion: String
    let suggestedTransferAnswer: String
    let sourceLabel: String
    let isDemo: Bool
}

@MainActor
protocol UnderstandingAssistanceProviding {
    func assistance(for exercise: String, subject: String, course: Course?) async throws -> UnderstandingAssistance
}

struct DemoUnderstandingAssistanceProvider: UnderstandingAssistanceProviding {
    func assistance(for exercise: String, subject: String, course: Course?) async throws -> UnderstandingAssistance {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? course?.name ?? "this subject"
        let shortExercise = exercise
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? "the exercise"

        return UnderstandingAssistance(
            hint: "Start by naming what the exercise asks you to find, then list the concepts from \(cleanSubject) that could apply before doing any calculation.",
            explanationSteps: [
                "Restate the task in your own words and identify the unknown.",
                "Write the relevant rule, formula, definition, or method before substituting values.",
                "Work through one transformation at a time and check whether each line follows from the previous one.",
                "Compare your final answer with the original question so you can justify why it answers the prompt."
            ],
            solution: "Demo guidance for: \(shortExercise). A real provider should generate a course-specific worked solution here. In demo mode, use the steps above to rebuild the answer and treat this text as a scaffold, not as an authoritative correction.",
            transferQuestion: "Create a similar \(cleanSubject) exercise by changing one value, example, or condition from the original. Solve it without looking back at the worked steps.",
            suggestedTransferAnswer: "Demo check: your transfer answer should show the same method, changed data or context, and a final justification in your own words.",
            sourceLabel: "Demo mode",
            isDemo: true
        )
    }
}

enum AIRevisionProviderStatus: Equatable {
    case notConfigured
    case ready
    case error(String)

    var title: String {
        switch self {
        case .notConfigured: "Non configuré"
        case .ready: "Prêt"
        case .error: "Erreur"
        }
    }
}

enum AIRevisionError: LocalizedError {
    case notConfigured
    case invalidProvider
    case missingAPIKey
    case emptyResponse
    case providerError(String)
    case redirected(String, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Aucun fournisseur IA n’est configuré."
        case .invalidProvider:
            return "Le fournisseur IA sélectionné n’est pas disponible."
        case .missingAPIKey:
            return "Aucune clé API IA n’est enregistrée dans le Keychain."
        case .emptyResponse:
            return "Le fournisseur IA n’a renvoyé aucun texte exploitable."
        case .providerError(let message):
            return message
        case .redirected(let expected, let actual):
            return "La requête IA a été redirigée de \(expected) vers \(actual). La réponse a été refusée pour protéger la clé API."
        }
    }
}

enum AIRevisionProviderID: String, CaseIterable, Identifiable, Codable {
    case openAI
    case claude
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Anthropic Claude"
        case .gemini: "Google Gemini"
        }
    }

    var officialDomain: String {
        switch self {
        case .openAI: "api.openai.com"
        case .claude: "api.anthropic.com"
        case .gemini: "generativelanguage.googleapis.com"
        }
    }

    var keyURL: URL {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .gemini: URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .claude: "claude-sonnet-4-5-20250929"
        case .gemini: "gemini-2.5-flash"
        }
    }

    var models: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]
        case .claude:
            return ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001", "claude-opus-4-5-20251101"]
        case .gemini:
            return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-1.5-flash", "gemini-1.5-pro"]
        }
    }
}

enum AIRevisionFundingMode: String, CaseIterable, Identifiable, Codable {
    case included
    case personalKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .included: "IA incluse avec UniSaver"
        case .personalKey: "Ma propre clé"
        }
    }

    var paymentDisclosure: String {
        switch self {
        case .included:
            return "Pris en charge par UniSaver lorsque le compte, l’abonnement et l’allocation serveur sont actifs."
        case .personalKey:
            return "Facturé par le fournisseur selon votre compte API personnel."
        }
    }
}

struct AIRevisionSettings {
    static let fundingModeKey = "aiRevisionFundingMode"
    static let activeProviderKey = "aiRevisionActiveProvider"
    static let promptVersion = "unisaver-study-session-v1"

    var fundingMode: AIRevisionFundingMode
    var activeProvider: AIRevisionProviderID
    var modelsByProvider: [AIRevisionProviderID: String]

    static var current: AIRevisionSettings {
        let defaults = UserDefaults.standard
        let fundingMode = AIRevisionFundingMode(rawValue: defaults.string(forKey: fundingModeKey) ?? AIRevisionFundingMode.personalKey.rawValue) ?? .personalKey
        let activeRaw = defaults.string(forKey: activeProviderKey) ?? AIRevisionProviderID.openAI.rawValue
        let activeProvider = AIRevisionProviderID(rawValue: activeRaw) ?? .openAI
        return AIRevisionSettings(
            fundingMode: fundingMode,
            activeProvider: activeProvider,
            modelsByProvider: Dictionary(uniqueKeysWithValues: AIRevisionProviderID.allCases.map { provider in
                (provider, defaults.string(forKey: modelKey(for: provider)) ?? provider.defaultModel)
            })
        )
    }

    static func modelKey(for provider: AIRevisionProviderID) -> String {
        "aiRevisionModel.\(provider.rawValue)"
    }

    static func testedKey(for provider: AIRevisionProviderID) -> String {
        "aiRevisionTested.\(provider.rawValue)"
    }

    var providerName: String {
        if fundingMode == .included {
            return "UniSaver Included AI"
        }
        return activeProvider.displayName
    }

    func model(for provider: AIRevisionProviderID? = nil) -> String {
        let provider = provider ?? activeProvider
        return modelsByProvider[provider]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? provider.defaultModel
    }

    func isTested(_ provider: AIRevisionProviderID? = nil) -> Bool {
        UserDefaults.standard.bool(forKey: Self.testedKey(for: provider ?? activeProvider))
    }
}

enum AIKeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): "Impossible d’enregistrer la clé IA dans le Keychain (\(status))."
        case .readFailed(let status): "Impossible de lire la clé IA dans le Keychain (\(status))."
        case .deleteFailed(let status): "Impossible de supprimer la clé IA du Keychain (\(status))."
        }
    }
}

struct AIKeychainStore {
    private let service = "UniSaver.AIRevision"

    private func account(for provider: AIRevisionProviderID) -> String {
        "providerAPIKey.\(provider.rawValue)"
    }

    func saveAPIKey(_ apiKey: String, for provider: AIRevisionProviderID) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AIKeychainError.saveFailed(updateStatus)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AIKeychainError.saveFailed(addStatus)
        }
    }

    func apiKey(for provider: AIRevisionProviderID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AIKeychainError.readFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey(for provider: AIRevisionProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainError.deleteFailed(status)
        }
    }
}

struct AIRevisionSource: Identifiable, Hashable {
    enum Kind: String {
        case note
        case resource
        case exercise
        case session
    }

    let id: String
    let title: String
    let kind: Kind
    let detail: String
    let text: String
    let sourceReference: String

    var hasUsableText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AIRevisionQuestionDraft: Identifiable {
    let id = UUID()
    var prompt: String
    var expectedAnswer: String
    var explanation: String
    var sourceReference: String
}

struct AIRevisionHistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let provider: AIRevisionProviderID
    let model: String
    let promptVersion: String
    let courseName: String
    let chapterTitle: String
    let objective: String
    let sourceReferences: [String]
}

enum AIRevisionHistoryStore {
    private static let storageKey = "aiRevisionHistory"

    static func load() -> [AIRevisionHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([AIRevisionHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func record(_ entry: AIRevisionHistoryEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func erase() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

enum AIRevisionMode {
    case explain
    case questionDrafts
    case progressiveHint
}

struct AIRevisionRequest {
    let courseName: String
    let chapterTitle: String
    let objective: String
    let mode: AIRevisionMode
    let sources: [AIRevisionSource]
}

struct AIRevisionResult {
    let content: String
    let provider: AIRevisionProviderID
    let model: String
    let promptVersion: String
}

protocol AIProvider {
    var id: AIRevisionProviderID { get }
    var model: String { get }
    func complete(systemPrompt: String, userPrompt: String) async throws -> String
}

struct AIRevisionAssistantClient {
    var settings: AIRevisionSettings = .current
    var keychain: AIKeychainStore = AIKeychainStore()
    var urlSession: URLSession = .shared

    func fundingModeStatus() -> AIRevisionProviderStatus {
        switch settings.fundingMode {
        case .included:
            return .notConfigured
        case .personalKey:
            return status(for: settings.activeProvider)
        }
    }

    func status(for provider: AIRevisionProviderID? = nil) -> AIRevisionProviderStatus {
        let provider = provider ?? settings.activeProvider
        do {
            guard try keychain.apiKey(for: provider) != nil else { return .notConfigured }
            return settings.isTested(provider) ? .ready : .notConfigured
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func status() -> AIRevisionProviderStatus {
        fundingModeStatus()
    }

    func testConnection(for provider: AIRevisionProviderID? = nil) async throws -> String {
        let provider = provider ?? settings.activeProvider
        let adapter = try adapter(for: provider)
        let answer = try await adapter.complete(
            systemPrompt: "You are a concise connectivity test for UniSaver. Reply with exactly: UniSaver AI ready.",
            userPrompt: "Test the connection."
        )
        UserDefaults.standard.set(true, forKey: AIRevisionSettings.testedKey(for: provider))
        return answer
    }

    func activeProviderSummary() -> String {
        switch settings.fundingMode {
        case .included:
            return "UniSaver Included AI · serveur UniSaver"
        case .personalKey:
            return "\(settings.activeProvider.displayName) · \(settings.model())"
        }
    }

    func paymentDisclosure() -> String {
        switch settings.fundingMode {
        case .included:
            return "Pris en charge par UniSaver. Ce mode nécessite un compte, un abonnement actif et une allocation serveur disponible."
        case .personalKey:
            return "Facturé par \(settings.activeProvider.displayName) selon votre compte API personnel."
        }
    }

    func explain(question: String, courseName: String, chapterTitle: String, sources: [AIRevisionSource]) async throws -> String {
        let result = try await run(
            AIRevisionRequest(
                courseName: courseName,
                chapterTitle: chapterTitle,
                objective: question,
                mode: .explain,
                sources: sources
            )
        )
        return result.content
    }

    func generateQuestions(courseName: String, chapterTitle: String, sources: [AIRevisionSource]) async throws -> [AIRevisionQuestionDraft] {
        let result = try await run(
            AIRevisionRequest(
                courseName: courseName,
                chapterTitle: chapterTitle,
                objective: "Préparer exactement trois questions de rappel en brouillon.",
                mode: .questionDrafts,
                sources: sources
            )
        )
        let parsed = parseQuestionDrafts(result.content)
        if parsed.isEmpty {
            return [
                AIRevisionQuestionDraft(
                    prompt: result.content,
                    expectedAnswer: "",
                    explanation: "Réponse brute du fournisseur. Vérifie et découpe cette proposition avant sauvegarde.",
                    sourceReference: sources.first?.sourceReference ?? "Sources sélectionnées"
                )
            ]
        }
        return parsed
    }

    func understandingAssistance(for exercise: String, subject: String, course: Course?) async throws -> UnderstandingAssistance {
        let result = try await run(
            AIRevisionRequest(
                courseName: course?.name ?? subject,
                chapterTitle: "Understanding Check",
                objective: """
                Exercice:
                \(exercise)

                Matière indiquée:
                \(subject)
                """,
                mode: .progressiveHint,
                sources: []
            )
        )
        return UnderstandingAssistance(
            hint: section("HINT", in: result.content) ?? "Indice indisponible dans la réponse du fournisseur.",
            explanationSteps: (section("STEPS", in: result.content) ?? result.content).split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            solution: section("SOLUTION", in: result.content) ?? "",
            transferQuestion: section("TRANSFER", in: result.content) ?? "Crée un exercice proche et tente-le sans regarder la solution.",
            suggestedTransferAnswer: section("TRANSFER_CHECK", in: result.content) ?? "Compare la méthode, les étapes et la justification finale.",
            sourceLabel: "\(result.provider.displayName) · \(result.model)",
            isDemo: false
        )
    }

    private func run(_ request: AIRevisionRequest) async throws -> AIRevisionResult {
        guard settings.fundingMode == .personalKey else {
            throw AIRevisionError.providerError("IA incluse avec UniSaver n’est pas encore disponible dans ce build : aucun backend de compte, d’abonnement ou de quota serveur n’est configuré. Sélectionnez explicitement « Ma propre clé » pour utiliser une clé personnelle.")
        }
        guard case .ready = status(for: settings.activeProvider) else {
            throw AIRevisionError.notConfigured
        }
        let adapter = try adapter(for: settings.activeProvider)
        let content = try await adapter.complete(
            systemPrompt: sourceBoundSystemPrompt(courseName: request.courseName, chapterTitle: request.chapterTitle),
            userPrompt: userPrompt(for: request)
        )
        AIRevisionHistoryStore.record(
            AIRevisionHistoryEntry(
                id: UUID(),
                createdAt: .now,
                provider: adapter.id,
                model: adapter.model,
                promptVersion: AIRevisionSettings.promptVersion,
                courseName: request.courseName,
                chapterTitle: request.chapterTitle,
                objective: request.objective,
                sourceReferences: request.sources.map(\.sourceReference)
            )
        )
        return AIRevisionResult(
            content: content,
            provider: adapter.id,
            model: adapter.model,
            promptVersion: AIRevisionSettings.promptVersion
        )
    }

    private func adapter(for provider: AIRevisionProviderID) throws -> AIProvider {
        let model = settings.model(for: provider)
        guard let apiKey = try keychain.apiKey(for: provider), !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIRevisionError.missingAPIKey
        }
        switch provider {
        case .openAI:
            return OpenAIRevisionProvider(model: model, apiKey: apiKey, urlSession: urlSession)
        case .claude:
            return ClaudeRevisionProvider(model: model, apiKey: apiKey, urlSession: urlSession)
        case .gemini:
            return GeminiRevisionProvider(model: model, apiKey: apiKey, urlSession: urlSession)
        }
    }

    private func sourceBoundSystemPrompt(courseName: String, chapterTitle: String) -> String {
        """
        UniSaver Study Session Contract \(AIRevisionSettings.promptVersion).
        Course: "\(courseName)".
        Chapter: "\(chapterTitle)".

        Method:
        1. Announce the learning objective and the selected sources you used.
        2. For exercises, ask the student to try first, then give a targeted hint before any full solution.
        3. Separate source-grounded statements from general explanations.
        4. Cite selected sources exactly with their Source Reference. If page or passage is provided, include it.
        5. If the selected sources do not contain the information, say so clearly.
        6. Correct after the student's attempt, then check understanding with a transfer question.
        7. Never modify or save UniSaver courses, chapters, notes, quizzes, flashcards, dates, or calendar events. Only draft editable suggestions.
        """
    }

    private func userPrompt(for request: AIRevisionRequest) -> String {
        switch request.mode {
        case .explain:
            return """
            Objective: explain the student's requested passage or notion.
            Student request:
            \(request.objective)

            Selected sources:
            \(sourceBlock(request.sources))
            """
        case .questionDrafts:
            return """
            Objective: prepare exactly 3 recall questions as editable drafts.
            Return plain text in this exact format:
            Q: ...
            A: ...
            E: ...
            S: ...

            Repeat the four lines for each question. S must name the source reference.

            Selected sources:
            \(sourceBlock(request.sources))
            """
        case .progressiveHint:
            return """
            Objective: progressive help for an exercise. Preserve this sequence: hint first, student attempt before solution, then transfer question.
            \(request.objective)

            Return:
            HINT:
            STEPS:
            SOLUTION:
            TRANSFER:
            TRANSFER_CHECK:
            """
        }
    }

    private func sourceBlock(_ sources: [AIRevisionSource]) -> String {
        sources.map { source in
            let cleanText = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let excerpt = cleanText.prefix(6_000)
            let omitted = cleanText.count > excerpt.count ? "\n[UniSaver: source truncated after \(excerpt.count) characters.]" : ""
            return """
            [\(source.sourceReference)]
            Title: \(source.title)
            Type: \(source.kind.rawValue)
            Text:
            \(excerpt)\(omitted)
            """
        }.joined(separator: "\n\n")
    }

    private func parseQuestionDrafts(_ raw: String) -> [AIRevisionQuestionDraft] {
        var drafts: [AIRevisionQuestionDraft] = []
        var current: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Q:") {
                if let draft = draft(from: current) { drafts.append(draft) }
                current = ["Q": String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)]
            } else if trimmed.hasPrefix("A:") {
                current["A"] = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("E:") {
                current["E"] = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("S:") {
                current["S"] = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let draft = draft(from: current) { drafts.append(draft) }
        return Array(drafts.prefix(3))
    }

    private func draft(from values: [String: String]) -> AIRevisionQuestionDraft? {
        guard let prompt = values["Q"], !prompt.isEmpty else { return nil }
        return AIRevisionQuestionDraft(
            prompt: prompt,
            expectedAnswer: values["A"] ?? "",
            explanation: values["E"] ?? "",
            sourceReference: values["S"] ?? "Sources sélectionnées"
        )
    }

    private func section(_ marker: String, in raw: String) -> String? {
        guard let range = raw.range(of: "\(marker):") else { return nil }
        let remainder = raw[range.upperBound...]
        let markers = ["HINT:", "STEPS:", "SOLUTION:", "TRANSFER:", "TRANSFER_CHECK:"].filter { $0 != "\(marker):" }
        let end = markers.compactMap { remainder.range(of: $0)?.lowerBound }.min() ?? remainder.endIndex
        let value = remainder[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct OpenAIRevisionProvider: AIProvider {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        struct ProviderError: Decodable {
            let message: String
        }
        let choices: [Choice]?
        let error: ProviderError?
    }

    let id: AIRevisionProviderID = .openAI
    let model: String
    let apiKey: String
    let urlSession: URLSession

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0.2
        ))
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, expectedHost: id.officialDomain)
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
        if let message = decoded?.error?.message {
            throw AIRevisionError.providerError(message)
        }
        try validateHTTP(response: response, data: data)
        guard let content = decoded?.choices?.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw AIRevisionError.emptyResponse
        }
        return content
    }
}

private struct ClaudeRevisionProvider: AIProvider {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]
    }

    struct ResponseBody: Decodable {
        struct Content: Decodable {
            let type: String
            let text: String?
        }
        struct ProviderError: Decodable {
            let message: String
        }
        let content: [Content]?
        let error: ProviderError?
    }

    let id: AIRevisionProviderID = .claude
    let model: String
    let apiKey: String
    let urlSession: URLSession

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            max_tokens: 1_800,
            temperature: 0.2,
            system: systemPrompt,
            messages: [Message(role: "user", content: userPrompt)]
        ))
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, expectedHost: id.officialDomain)
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
        if let message = decoded?.error?.message {
            throw AIRevisionError.providerError(message)
        }
        try validateHTTP(response: response, data: data)
        let content = decoded?.content?.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else {
            throw AIRevisionError.emptyResponse
        }
        return content
    }
}

private struct GeminiRevisionProvider: AIProvider {
    struct TextPart: Codable {
        let text: String
    }

    struct Content: Codable {
        let role: String?
        let parts: [TextPart]
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
    }

    struct RequestBody: Encodable {
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    struct ResponseBody: Decodable {
        struct Candidate: Decodable {
            let content: Content?
        }
        struct ProviderError: Decodable {
            let message: String
        }
        let candidates: [Candidate]?
        let error: ProviderError?
    }

    let id: AIRevisionProviderID = .gemini
    let model: String
    let apiKey: String
    let urlSession: URLSession

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            systemInstruction: Content(role: nil, parts: [TextPart(text: systemPrompt)]),
            contents: [Content(role: "user", parts: [TextPart(text: userPrompt)])],
            generationConfig: GenerationConfig(temperature: 0.2)
        ))
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, expectedHost: id.officialDomain)
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
        if let message = decoded?.error?.message {
            throw AIRevisionError.providerError(message)
        }
        try validateHTTP(response: response, data: data)
        let content = decoded?.candidates?.first?.content?.parts.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else {
            throw AIRevisionError.emptyResponse
        }
        return content
    }
}

private func validate(response: URLResponse, expectedHost: String) throws {
    guard let actualHost = response.url?.host?.lowercased() else { return }
    if actualHost != expectedHost.lowercased() {
        throw AIRevisionError.redirected(expectedHost, actualHost)
    }
}

private func validateHTTP(response: URLResponse, data: Data) throws {
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(statusCode) else {
        let raw = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
        throw AIRevisionError.providerError(raw)
    }
}

struct UnderstandingProgressSummary {
    let attemptCount: Int
    let independentCount: Int
    let partialCount: Int
    let averageRedoProgress: Double
    let latest: UnderstandingPracticeAttempt?

    var completedCheckCount: Int {
        independentCount + partialCount
    }
}

enum UnderstandingPracticeService {
    static func strongestHelpLevel(
        current: UnderstandingHelpLevel,
        didRevealHint: Bool,
        revealedStepCount: Int,
        didRevealSolution: Bool
    ) -> UnderstandingHelpLevel {
        if didRevealSolution { return max(current, .solution) }
        if revealedStepCount > 0 { return max(current, .steps) }
        if didRevealHint { return max(current, .hint) }
        return current
    }

    static func progressSummary(for attempts: [UnderstandingPracticeAttempt]) -> UnderstandingProgressSummary {
        let checked = attempts.filter { $0.autonomousResult != .notChecked }
        let independent = checked.filter { $0.autonomousResult == .independent }.count
        let partial = checked.filter { $0.autonomousResult == .partial }.count
        let average = checked.isEmpty
            ? 0
            : checked.reduce(0) { $0 + $1.autonomousResult.progressValue } / Double(checked.count)
        let latest = attempts.sorted { $0.createdAt > $1.createdAt }.first
        return UnderstandingProgressSummary(
            attemptCount: attempts.count,
            independentCount: independent,
            partialCount: partial,
            averageRedoProgress: average,
            latest: latest
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
