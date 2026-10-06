import Foundation

enum MoodleClientError: LocalizedError, Equatable {
    case invalidHTTPSURL
    case missingAuthorizedToken
    case connectionUnavailable
    case capabilityUnavailable(String)
    case permissionDenied(String)
    case sessionExpired
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHTTPSURL:
            "Enter a valid HTTPS Moodle URL."
        case .missingAuthorizedToken:
            "Connexion indisponible pour cet établissement. UniSaver needs an authorized read-only Moodle web service token provided by the institution."
        case .connectionUnavailable:
            "Connexion indisponible pour cet établissement."
        case .capabilityUnavailable(let function):
            "Moodle function unavailable: \(function)."
        case .permissionDenied(let message):
            "Moodle refused access: \(message)"
        case .sessionExpired:
            "The Moodle session expired. Reconnect with an authorized token."
        case .network(let message):
            "Network error: \(message)"
        case .invalidResponse:
            "Moodle returned an unexpected response."
        }
    }
}

struct MoodleSiteInfo: Decodable {
    struct FunctionInfo: Decodable {
        let name: String
    }

    let sitename: String?
    let fullname: String?
    let userid: Int
    let functions: [FunctionInfo]?

    var availableFunctionNames: Set<String> {
        Set(functions?.map(\.name) ?? [])
    }
}

struct MoodleCourseDTO: Decodable, Hashable {
    let id: Int
    let fullname: String
    let shortname: String?
    let viewurl: URL?
    let summary: String?
    let startdate: Int?
    let enddate: Int?
}

struct MoodleEventDTO: Decodable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let timestart: Int?
    let timeduration: Int?
    let url: URL?
    let courseid: Int?
    let modulename: String?
}

struct MoodleClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    init(institutionURL: URL, token: String) throws {
        guard institutionURL.scheme?.lowercased() == "https" else {
            throw MoodleClientError.invalidHTTPSURL
        }
        self.baseURL = institutionURL
        self.token = token
    }

    func siteInfo() async throws -> MoodleSiteInfo {
        try await request("core_webservice_get_site_info", parameters: [:])
    }

    func enrolledCourses(for userID: Int, availableFunctions: Set<String>) async throws -> [MoodleCourseDTO] {
        try require("core_enrol_get_users_courses", in: availableFunctions)
        return try await request("core_enrol_get_users_courses", parameters: ["userid": String(userID)])
    }

    func actionEvents(courseIDs: [Int], availableFunctions: Set<String>) async throws -> [MoodleEventDTO] {
        try require("core_calendar_get_action_events_by_courses", in: availableFunctions)
        var parameters: [String: String] = [:]
        for (index, courseID) in courseIDs.enumerated() {
            parameters["courseids[\(index)]"] = String(courseID)
        }
        let response: MoodleActionEventsResponse = try await request("core_calendar_get_action_events_by_courses", parameters: parameters)
        return response.groupedByCourse.compactMap(\.events).flatMap { $0 }
    }

    private func require(_ function: String, in availableFunctions: Set<String>) throws {
        guard availableFunctions.contains(function) else {
            throw MoodleClientError.capabilityUnavailable(function)
        }
    }

    private func request<T: Decodable>(_ function: String, parameters: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: "webservice/rest/server.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "moodlewsrestformat", value: "json"),
            URLQueryItem(name: "wstoken", value: token),
            URLQueryItem(name: "wsfunction", value: function)
        ] + parameters.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }

        guard let url = components?.url else {
            throw MoodleClientError.invalidHTTPSURL
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MoodleClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw MoodleClientError.network("HTTP \(httpResponse.statusCode)")
            }
            if let exception = try? JSONDecoder().decode(MoodleExceptionResponse.self, from: data) {
                throw exception.asClientError
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as MoodleClientError {
            throw error
        } catch {
            throw MoodleClientError.network(error.localizedDescription)
        }
    }
}

private struct MoodleExceptionResponse: Decodable {
    let exception: String?
    let errorcode: String?
    let message: String?

    var asClientError: MoodleClientError {
        let code = errorcode ?? ""
        if code.localizedCaseInsensitiveContains("invalidtoken") {
            return .sessionExpired
        }
        if code.localizedCaseInsensitiveContains("access") || code.localizedCaseInsensitiveContains("permission") {
            return .permissionDenied(message ?? code)
        }
        return .network(message ?? code)
    }
}

private struct MoodleActionEventsResponse: Decodable {
    struct CourseEvents: Decodable {
        let events: [MoodleEventDTO]?
    }

    let groupedByCourse: [CourseEvents]

    enum CodingKeys: String, CodingKey {
        case groupedByCourse = "groupedbycourse"
    }
}
