import Foundation
import SwiftUI

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let imageData: Data?
}

struct WorkflowStep: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let detail: String
    let actionPrompt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case actionPrompt = "action_prompt"
    }
}

final class AppState: ObservableObject {
    enum ChatProvider: String, CaseIterable, Identifiable {
        case openAI = "OpenAI"
        case ollama = "Ollama"

        var id: String { rawValue }
    }

    @Published var currentPrompt: String = ""
    @Published var isProcessing: Bool = false
    @Published var videoURL: URL?
    @Published var workflowSteps: [WorkflowStep] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var statusText: String?
    @Published var sessionId: String?
    @Published var chatProvider: ChatProvider = .ollama

    private let odysseyClient: OdysseyClient
    private let ollamaClient: OllamaClient
    private let openAIClient: OpenAIClient?
    private let screenshotService: ScreenshotService

    init(
        odysseyClient: OdysseyClient = OdysseyClient(),
        ollamaClient: OllamaClient = OllamaClient(),
        openAIClient: OpenAIClient? = OpenAIClient(),
        screenshotService: ScreenshotService = ScreenshotService()
    ) {
        self.odysseyClient = odysseyClient
        self.ollamaClient = ollamaClient
        if let client = openAIClient, client.hasAPIKey {
            self.openAIClient = client
            self.chatProvider = .openAI
        } else {
            self.openAIClient = nil
            self.chatProvider = .ollama
        }
        self.screenshotService = screenshotService
    }

    func handleUserPrompt() {
        let trimmed = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await generateFromPrompt(prompt: trimmed)
        }
    }

    func handleWorkflowStepTap(_ step: WorkflowStep) {
        let prompt = step.actionPrompt ?? step.title
        Task {
            await refineStream(prompt: prompt)
        }
    }

    func sendChat(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMessage = ChatMessage(role: .user, text: trimmed, imageData: nil)
        chatMessages.append(userMessage)
        Task {
            await sendChatToAI(message: trimmed)
        }
    }

    func addScreenshotMessage() {
        guard let data = screenshotService.captureMainDisplayExcludingAppWindowPNGData() else {
            let errorMessage = ChatMessage(
                role: .assistant,
                text: "Failed to capture screenshot",
                imageData: nil
            )
            chatMessages.append(errorMessage)
            return
        }
        let message = ChatMessage(
            role: .user,
            text: "Screenshot",
            imageData: data
        )
        chatMessages.append(message)
    }

    @MainActor
    private func updateStatus(_ text: String?) {
        statusText = text
    }

    private func generateFromPrompt(prompt: String) async {
        await MainActor.run {
            isProcessing = true
            statusText = "Contacting Odyssey"
        }
        let screenshotData = screenshotService.captureMainDisplayPNGData()
        do {
            let response = try await odysseyClient.startStream(
                prompt: prompt,
                screenshotPNGData: screenshotData
            )
            await MainActor.run {
                videoURL = response.stream.url
                workflowSteps = response.steps
                sessionId = response.sessionId
                isProcessing = false
                statusText = nil
            }
        } catch {
            await MainActor.run {
                statusText = "Odyssey error: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func sendChatToAI(message: String) async {
        switch chatProvider {
        case .openAI:
            guard let openAIClient else {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    text: "OpenAI is not configured. Set OPENAI_API_KEY or switch to Ollama.",
                    imageData: nil
                )
                await MainActor.run {
                    chatMessages.append(errorMessage)
                }
                return
            }
            await sendChatToOpenAI(message: message, client: openAIClient)
        case .ollama:
            await sendChatToOllama(message: message)
        }
    }

    private func sendChatToOpenAI(message: String, client: OpenAIClient) async {
        do {
            let reply = try await client.send(
                message: message,
                previousMessages: chatMessages
            )
            let assistantMessage = ChatMessage(role: .assistant, text: reply, imageData: nil)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
        } catch {
            let errorMessage = ChatMessage(
                role: .assistant,
                text: "OpenAI error: \(error.localizedDescription)",
                imageData: nil
            )
            await MainActor.run {
                chatMessages.append(errorMessage)
            }
        }
    }

    private func refineStream(prompt: String) async {
        await MainActor.run {
            isProcessing = true
            statusText = "Refining stream"
        }
        let screenshotData = screenshotService.captureMainDisplayPNGData()
        do {
            if let sessionId {
                let response = try await odysseyClient.refineStream(
                    sessionId: sessionId,
                    prompt: prompt,
                    screenshotPNGData: screenshotData
                )
                await MainActor.run {
                    videoURL = response.stream.url
                    workflowSteps = response.steps
                    self.sessionId = response.sessionId ?? sessionId
                    isProcessing = false
                    statusText = nil
                }
            } else {
                await generateFromPrompt(prompt: prompt)
            }
        } catch {
            await MainActor.run {
                statusText = "Odyssey error: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func sendChatToOllama(message: String) async {
        do {
            let reply = try await ollamaClient.send(
                message: message,
                previousMessages: chatMessages
            )
            let assistantMessage = ChatMessage(role: .assistant, text: reply, imageData: nil)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
        } catch {
            let errorMessage = ChatMessage(
                role: .assistant,
                text: "Ollama error: \(error.localizedDescription)",
                imageData: nil
            )
            await MainActor.run {
                chatMessages.append(errorMessage)
            }
        }
    }
}
