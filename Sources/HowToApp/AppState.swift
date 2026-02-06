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
    @Published var currentPrompt: String = ""
    @Published var isProcessing: Bool = false
    @Published var videoURL: URL?
    @Published var workflowSteps: [WorkflowStep] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var statusText: String?
    @Published var sessionId: String?

    private let odysseyClient: OdysseyClient
    private let ollamaClient: OllamaClient
    private let screenshotService: ScreenshotService

    init(
        odysseyClient: OdysseyClient = OdysseyClient(),
        ollamaClient: OllamaClient = OllamaClient(),
        screenshotService: ScreenshotService = ScreenshotService()
    ) {
        self.odysseyClient = odysseyClient
        self.ollamaClient = ollamaClient
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
        let userMessage = ChatMessage(role: .user, text: trimmed)
        chatMessages.append(userMessage)
        Task {
            await sendChatToOllama(message: trimmed)
        }
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
            let assistantMessage = ChatMessage(role: .assistant, text: reply)
            await MainActor.run {
                chatMessages.append(assistantMessage)
            }
        } catch {
            let errorMessage = ChatMessage(
                role: .assistant,
                text: "Ollama error: \(error.localizedDescription)"
            )
            await MainActor.run {
                chatMessages.append(errorMessage)
            }
        }
    }
}
