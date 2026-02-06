import Foundation

struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let message: Message
}

enum OllamaError: LocalizedError {
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}

final class OllamaClient {
    private let baseURL: URL
    private let model: String

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        model: String = "llama3.2:3b"
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    func send(
        message: String,
        previousMessages: [ChatMessage]
    ) async throws -> String {
        let history = previousMessages.map { previous in
            OllamaChatRequest.Message(
                role: previous.role == .user ? "user" : "assistant",
                content: previous.text
            )
        }
        let payload = OllamaChatRequest(
            model: model,
            messages: history + [
                OllamaChatRequest.Message(role: "user", content: message)
            ],
            stream: false
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return decoded.message.content
    }
}
