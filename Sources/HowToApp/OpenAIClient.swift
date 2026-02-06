import Foundation

struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        struct Content: Encodable {
            struct ImageURL: Encodable {
                let url: String
            }

            let type: String
            let text: String?
            let image_url: ImageURL?
        }

        let role: String
        let content: [Content]
    }

    let model: String
    let messages: [Message]
}

struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }

            let role: String
            let content: [Content]
        }

        let index: Int
        let message: Message
        let finish_reason: String?
    }

    let choices: [Choice]
}

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case httpError(statusCode: Int, message: String)
    case decodingError(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key. Set OPENAI_API_KEY or define it in .env."
        case let .httpError(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        case let .decodingError(message):
            return "Failed to parse OpenAI response: \(message)"
        }
    }
}

final class OpenAIClient {
    private let apiKey: String
    private let baseURL: URL
    private let model: String

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4o-mini"
    ) {
        let envFromFile = OpenAIClient.loadEnvFromFile()
        self.apiKey = apiKey ?? envFromFile ?? ""
        self.baseURL = baseURL
        self.model = model
    }

    private static func loadEnvFromFile() -> String? {
        let fileURL = URL(fileURLWithPath: #file)
        let packageRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = packageRoot.appendingPathComponent(".env")
        guard let data = try? Data(contentsOf: envURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        var apiKey: String?
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            if key == "OPENAI_API_KEY" || key == "OpenAI_API_Key" {
                apiKey = value
            }
        }
        return apiKey
    }

    func send(
        message: String,
        previousMessages: [ChatMessage]
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }

        let history = previousMessages.map { previous in
            OpenAIChatRequest.Message(
                role: previous.role == .user ? "user" : "assistant",
                content: OpenAIClient.buildContent(from: previous)
            )
        }

        let latest = ChatMessage(
            role: .user,
            text: message,
            imageData: nil
        )

        let payload = OpenAIChatRequest(
            model: model,
            messages: history + [
                OpenAIChatRequest.Message(
                    role: "user",
                    content: OpenAIClient.buildContent(from: latest)
                )
            ]
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(statusCode: -1, message: "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let first = decoded.choices.first else {
                throw OpenAIError.decodingError(message: "No choices in response")
            }
            let textParts = first.message.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
            return textParts.joined(separator: "\n")
        } catch let error as OpenAIError {
            throw error
        } catch {
            throw OpenAIError.decodingError(message: error.localizedDescription)
        }
    }

    private static func buildContent(from message: ChatMessage) -> [OpenAIChatRequest.Message.Content] {
        var contents: [OpenAIChatRequest.Message.Content] = []
        if !message.text.isEmpty {
            contents.append(
                OpenAIChatRequest.Message.Content(
                    type: "text",
                    text: message.text,
                    image_url: nil
                )
            )
        }
        if let data = message.imageData {
            let base64 = data.base64EncodedString()
            let url = "data:image/png;base64,\(base64)"
            contents.append(
                OpenAIChatRequest.Message.Content(
                    type: "image_url",
                    text: nil,
                    image_url: OpenAIChatRequest.Message.Content.ImageURL(url: url)
                )
            )
        }
        return contents
    }
}

