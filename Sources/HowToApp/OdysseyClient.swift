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
}

struct OdysseyJobResponse: Decodable {
    let id: String
}

struct OdysseyJobStatus: Decodable {
    let status: String
    let outputURL: URL?

    enum CodingKeys: String, CodingKey {
        case status
        case outputURL = "output_url"
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
    private let generatePath: String
    private let jobsPath: String

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["ODYSSEY_API_KEY"],
        developerEmail: String? = ProcessInfo.processInfo.environment["ODYSSEY_DEVELOPER_EMAIL"],
        baseURL: URL = URL(string: "https://api.odyssey.ml")!
    ) {
        let envFromFile = OdysseyClient.loadEnvFromFile()
        let processEnv = ProcessInfo.processInfo.environment
        let resolvedBaseURLString = processEnv["ODYSSEY_BASE_URL"] ?? envFromFile.baseURL
        let resolvedBaseURL = URL(string: resolvedBaseURLString ?? "") ?? baseURL
        self.apiKey = apiKey ?? processEnv["ODYSSEY_API_KEY"] ?? envFromFile.apiKey ?? ""
        self.developerEmail = developerEmail
            ?? processEnv["ODYSSEY_DEVELOPER_EMAIL"]
            ?? envFromFile.developerEmail
            ?? ""
        self.baseURL = resolvedBaseURL
        self.generatePath = processEnv["ODYSSEY_GENERATE_PATH"]
            ?? envFromFile.generatePath
            ?? "v1/generate"
        self.jobsPath = processEnv["ODYSSEY_JOBS_PATH"]
            ?? envFromFile.jobsPath
            ?? "v1/jobs"
    }

    private static func loadEnvFromFile() -> (
        apiKey: String?,
        developerEmail: String?,
        baseURL: String?,
        generatePath: String?,
        jobsPath: String?
    ) {
        let fileURL = URL(fileURLWithPath: #file)
        let packageRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = packageRoot.appendingPathComponent(".env")
        guard let data = try? Data(contentsOf: envURL),
              let content = String(data: data, encoding: .utf8) else {
            return (nil, nil, nil, nil, nil)
        }
        var apiKey: String?
        var developerEmail: String?
        var baseURL: String?
        var generatePath: String?
        var jobsPath: String?
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
            } else if key == "ODYSSEY_BASE_URL" {
                baseURL = value
            } else if key == "ODYSSEY_GENERATE_PATH" {
                generatePath = value
            } else if key == "ODYSSEY_JOBS_PATH" {
                jobsPath = value
            }
        }
        return (apiKey, developerEmail, baseURL, generatePath, jobsPath)
    }

    private func makeEndpointURL(path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    func startStream(
        prompt: String,
        screenshotPNGData: Data?
    ) async throws -> OdysseyResponse {
        guard !apiKey.isEmpty else {
            throw OdysseyError.missingCredentials
        }
        let endpoint = makeEndpointURL(path: generatePath)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if !developerEmail.isEmpty {
            request.setValue(developerEmail, forHTTPHeaderField: "X-Developer-Email")
        }
        let body: [String: Any] = [
            "prompt": prompt,
            "duration": 4,
            "aspect_ratio": "16:9"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdysseyError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            let fullMessage = "\(message) (url: \(endpoint.absoluteString))"
            throw OdysseyError.httpError(statusCode: httpResponse.statusCode, message: fullMessage)
        }
        let job = try JSONDecoder().decode(OdysseyJobResponse.self, from: data)
        let videoURL = try await waitForVideo(jobId: job.id)
        let stream = OdysseyStream(url: videoURL)
        return OdysseyResponse(stream: stream, steps: [], sessionId: nil)
    }

    func refineStream(
        sessionId: String,
        prompt: String,
        screenshotPNGData: Data?
    ) async throws -> OdysseyResponse {
        return try await startStream(prompt: prompt, screenshotPNGData: screenshotPNGData)
    }

    private func waitForVideo(jobId: String) async throws -> URL {
        while true {
            let endpoint = makeEndpointURL(path: "\(jobsPath)/\(jobId)")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OdysseyError.httpError(statusCode: -1, message: "Invalid response")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                let fullMessage = "\(message) (url: \(endpoint.absoluteString))"
                throw OdysseyError.httpError(statusCode: httpResponse.statusCode, message: fullMessage)
            }
            let status = try JSONDecoder().decode(OdysseyJobStatus.self, from: data)
            if status.status == "completed", let url = status.outputURL {
                return url
            }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}
