import Foundation

struct OdysseyRequestBody: Encodable {
    let prompt: String
    let screenshot: String?
}

struct OdysseyStream: Decodable {
    let url: URL
}

struct OdysseyResponse: Decodable {
    let stream: OdysseyStream
    let steps: [WorkflowStep]
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case stream
        case steps = "workflow"
        case sessionId = "session_id"
    }
}

enum OdysseyError: LocalizedError {
    case missingCredentials
    case httpError(statusCode: Int, message: String)
    case decodingError(message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing Odyssey credentials. Set ODYSSEY_API_KEY (and optionally ODYSSEY_DEVELOPER_EMAIL)."
        case let .httpError(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        case let .decodingError(message):
            return "Failed to parse Odyssey response: \(message)"
        }
    }
}

final class OdysseyClient {
    private let apiKey: String
    private let developerEmail: String
    private let baseURL: URL

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["ODYSSEY_API_KEY"],
        developerEmail: String? = ProcessInfo.processInfo.environment["ODYSSEY_DEVELOPER_EMAIL"],
        baseURL: URL = URL(string: "https://api.odyssey.ml")!
    ) {
        let envFromFile = OdysseyClient.loadEnvFromFile()
        self.apiKey = apiKey ?? envFromFile.apiKey ?? ""
        self.developerEmail = developerEmail ?? envFromFile.developerEmail ?? ""
        self.baseURL = baseURL
    }

    private static func loadEnvFromFile() -> (apiKey: String?, developerEmail: String?) {
        let fileURL = URL(fileURLWithPath: #file)
        let packageRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = packageRoot.appendingPathComponent(".env")
        guard let data = try? Data(contentsOf: envURL),
              let content = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }
        var apiKey: String?
        var developerEmail: String?
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            if key == "ODYSSEY_API_KEY" {
                apiKey = value
            } else if key == "ODYSSEY_DEVELOPER_EMAIL" {
                developerEmail = value
            }
        }
        return (apiKey, developerEmail)
    }

    func startStream(
        prompt: String,
        screenshotPNGData: Data?
    ) async throws -> OdysseyResponse {
        guard !apiKey.isEmpty else {
            throw OdysseyError.missingCredentials
        }
        let endpoint = baseURL.appendingPathComponent("v1/interactive_streams")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if !developerEmail.isEmpty {
            request.setValue(developerEmail, forHTTPHeaderField: "X-Developer-Email")
        }
        let body = OdysseyRequestBody(
            prompt: prompt,
            screenshot: screenshotPNGData?.base64EncodedString()
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdysseyError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OdysseyError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(OdysseyResponse.self, from: data)
        } catch {
            throw OdysseyError.decodingError(message: error.localizedDescription)
        }
    }

    func refineStream(
        sessionId: String,
        prompt: String,
        screenshotPNGData: Data?
    ) async throws -> OdysseyResponse {
        guard !apiKey.isEmpty else {
            throw OdysseyError.missingCredentials
        }
        let endpoint = baseURL.appendingPathComponent("v1/interactive_streams/\(sessionId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if !developerEmail.isEmpty {
            request.setValue(developerEmail, forHTTPHeaderField: "X-Developer-Email")
        }
        let body = OdysseyRequestBody(
            prompt: prompt,
            screenshot: screenshotPNGData?.base64EncodedString()
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdysseyError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OdysseyError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(OdysseyResponse.self, from: data)
        } catch {
            throw OdysseyError.decodingError(message: error.localizedDescription)
        }
    }
}
