import Foundation

struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
        let images: [String]?
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
    private let logStore: LogStore

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        model: String = "llama3.2-vision:11b",
        logStore: LogStore = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.logStore = logStore
    }

    func send(
        message: String,
        previousMessages: [ChatMessage]
    ) async throws -> String {
        let history = previousMessages.map { previous in
            OllamaChatRequest.Message(
                role: previous.role == .user ? "user" : "assistant",
                content: previous.text,
                images: previous.imageData.map { [ $0.base64EncodedString() ] }
            )
        }
        let payload = OllamaChatRequest(
            model: model,
            messages: history + [
                OllamaChatRequest.Message(role: "user", content: message, images: nil)
            ],
            stream: false
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        let endpoint = request.url
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        Task { @MainActor in
            logStore.log(.info, service: "Ollama", message: "Request start", url: endpoint)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Task { @MainActor in
                logStore.log(.error, service: "Ollama", message: "Invalid response", url: endpoint)
            }
            throw OllamaError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            Task { @MainActor in
                logStore.log(.error, service: "Ollama", message: message, url: endpoint, statusCode: httpResponse.statusCode)
            }
            throw OllamaError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        Task { @MainActor in
            logStore.log(.info, service: "Ollama", message: "Request succeeded", url: endpoint, statusCode: httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return decoded.message.content
    }
}
