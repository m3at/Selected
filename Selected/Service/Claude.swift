//
//  Claude.swift
//  Selected
//
//  Created by sake on 2024/7/13.
//

import Foundation
import SwiftAnthropic
import Defaults

// MARK: - Model and Extensions

public typealias ClaudeModel = Model

extension ClaudeModel: @retroactive CaseIterable {
    public static var allCases: [SwiftAnthropic.Model] {
        [.claude37Sonnet, .claude35Haiku, .claude35Sonnet]
    }
}

// MARK: - Tool Use Data Model

fileprivate struct ToolUse {
    let id: String
    let name: String
    var input: String
}

// MARK: - Tool Management Module

fileprivate struct ToolsManager {

    /// Generate tool descriptions from a list of FunctionDefinition
    static func generateTools(from functions: [FunctionDefinition]?) -> [MessageParameter.Tool] {
        guard let functions = functions else { return [] }
        var tools = [MessageParameter.Tool]()
        for fc in functions {
            let schema = try! JSONDecoder().decode(JSONSchema.self, from: fc.parameters.data(using: .utf8)!)
            let tool = MessageParameter.Tool.function(name: fc.name, description: fc.description, inputSchema: schema)
            tools.append(tool)
        }
        return tools
    }

    /// Call corresponding tool functions based on the tool use list and return tool call result messages
    static func callTools(
        index: inout Int,
        toolUseList: [ToolUse],
        with functionDefinitions: [FunctionDefinition],
        options: [String: String],
        completion: @escaping (_: Int, _: ResponseMessage) -> Void
    ) async throws -> [MessageParameter.Message] {
        index += 1
        var fcSet = [String: FunctionDefinition]()
        for fc in functionDefinitions {
            fcSet[fc.name] = fc
        }
        var toolUseResults = [MessageParameter.Message.Content.ContentObject]()

        for tool in toolUseList {
            if tool.name == "display_svg" {
                let rawMessage = String(format: NSLocalizedString("calling_tool", comment: "tool message"), tool.name)
                var message = ResponseMessage(message: rawMessage, role: .tool, new: true, status: .updating)
                completion(index, message)
                // Open SVG browser for preview
                _ = openSVGInBrowser(svgData: tool.input)
                message = ResponseMessage(message: String(format: NSLocalizedString("display_svg", comment: "")), role: .tool, new: true, status: .finished)
                completion(index, message)
                toolUseResults.append(.toolResult(tool.id, "display svg successfully"))
                continue
            }

            guard let fc = fcSet[tool.name] else { continue }
            let rawMessage = String(format: NSLocalizedString("calling_tool", comment: "tool message"), tool.name)
            let message = ResponseMessage(message: rawMessage, role: .tool, new: true, status: .updating)
            if let template = fc.template {
                message.message = renderTemplate(templateString: template, json: tool.input)
            }
            completion(index, message)

            if let ret = try fc.Run(arguments: tool.input, options: options) {
                let resultMessage = ResponseMessage(message: ret, role: .tool, new: true, status: .finished)
                if let show = fc.showResult, !show {
                    resultMessage.message = fc.template != nil ? "" : String(format: NSLocalizedString("called_tool", comment: "tool message"), fc.name)
                }
                completion(index, resultMessage)
                toolUseResults.append(.toolResult(tool.id, ret))
            }
        }
        return [.init(role: .user, content: .list(toolUseResults))]
    }
}

// MARK: - Query Management Module

struct QueryManager {
    private(set) var query: MessageParameter
    private let _tools: [MessageParameter.Tool]

    init(model: Model, systemPrompt: String, tools: [MessageParameter.Tool]) {
        var thinking: MessageParameter.Thinking? = nil
        if model.value == Model.claude37Sonnet.value {
            thinking = .init(budgetTokens: 2048)
        }
        self.query = MessageParameter(
            model: .other(model.value),
            messages: [],
            maxTokens: 4096,
            system: MessageParameter.System.text(systemPrompt),
            tools: tools,
            thinking: thinking
        )
        self._tools = tools
    }

    mutating func update(with message: MessageParameter.Message) {
        var messages = query.messages
        messages.append(message)
        query = MessageParameter(
            model: .other(query.model),
            messages: messages,
            maxTokens: 4096,
            system: query.system,
            tools: self._tools,
            thinking: query.thinking
        )
    }

    mutating func update(with messages: [MessageParameter.Message]) {
        var _messages = query.messages
        _messages.append(contentsOf: messages)
        query = MessageParameter(
            model: .other(query.model),
            messages: _messages,
            maxTokens: 4096,
            system: query.system,
            tools: self._tools,
            thinking: query.thinking
        )
    }
}

// MARK: - Chat Service Module

class ClaudeService: AIChatService {
    private let service: AnthropicService
    private let prompt: String
    private let options: [String: String]
    private var queryManager: QueryManager
    private let tools: [FunctionDefinition]?

    init(prompt: String, tools: [FunctionDefinition]? = nil, options: [String: String] = [:]) {
        var apiHost = "https://api.anthropic.com"
        if Defaults[.claudeAPIHost] != "" {
            apiHost = Defaults[.claudeAPIHost]
        }
        service = AnthropicServiceFactory.service(apiKey: Defaults[.claudeAPIKey], basePath: apiHost, betaHeaders: nil)
        self.prompt = prompt
        self.options = options

        // Generate tool descriptions and add SVG tool
        var toolsParam = ToolsManager.generateTools(from: tools)
        toolsParam.append(svgToolClaudeDef)
        self.tools = tools
        self.queryManager = QueryManager(model: .other(Defaults[.claudeModel]), systemPrompt: systemPrompt(), tools: toolsParam)
    }

    /// Single chat: send only one message, return streaming response content
    func chatOne(selectedText: String, completion: @escaping (_: String) -> Void) async {
        let userMessage = replaceOptions(content: prompt, selectedText: selectedText, options: options)
        let parameters = MessageParameter(
            model: .claude35Sonnet,
            messages: [.init(role: .user, content: .text(userMessage))],
            maxTokens: 4096
        )
        do {
            let stream = try await service.streamMessage(parameters)
            for try await result in stream {
                let content = result.delta?.text ?? ""
                if !content.isEmpty {
                    completion(content)
                }
            }
        } catch {
            print("claude error \(error)")
        }
    }

    /// Chat follow-up: append user message, and process in a loop until a complete reply is received
    func chatFollow(index: Int, userMessage: String, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async {
        queryManager.update(with: .init(role: .user, content: .text(userMessage)))
        var newIndex = index
        while let last = queryManager.query.messages.last, last.role != MessageParameter.Message.Role.assistant.rawValue {
            do {
                try await chatOneRound(index: &newIndex, completion: completion)
            } catch {
                newIndex += 1
                let localMsg = String(format: NSLocalizedString("error_exception", comment: "system info"), error as CVarArg)
                let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                completion(newIndex, message)
                return
            }
            if newIndex - index >= MAX_CHAT_ROUNDS {
                newIndex += 1
                let localMsg = NSLocalizedString("Too much rounds, please start a new chat", comment: "system info")
                let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                completion(newIndex, message)
                return
            }
        }
    }

    /// Conduct a conversation based on the chat context
    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async {
        var userMessage = renderChatContent(content: prompt, chatCtx: ctx, options: options)
        userMessage = replaceOptions(content: userMessage, selectedText: ctx.text, options: options)
        queryManager.update(with: .init(role: .user, content: .text(userMessage)))
        var index = -1
        while let last = queryManager.query.messages.last, last.role != MessageParameter.Message.Role.assistant.rawValue {
            do {
                try await chatOneRound(index: &index, completion: completion)
            } catch {
                index += 1
                let localMsg = String(format: NSLocalizedString("error_exception", comment: "system info"), error as CVarArg)
                let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                completion(index, message)
                return
            }
            if index >= MAX_CHAT_ROUNDS {
                index += 1
                let localMsg = NSLocalizedString("Too much rounds, please start a new chat", comment: "system info")
                let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                completion(index, message)
                return
            }
        }
    }

    /// Single round chat processing: receive reply in stream, and handle possible tool calls
    private func chatOneRound(index: inout Int, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async throws {
        print("index is \(index)")
        var assistantMessage = ""
        var thinking = ""
        var toolParameters = ""
        var signature = ""
        var toolUseList = [ToolUse]()
        var lastToolUseBlockIndex = -1

        completion(index + 1, ResponseMessage(message: NSLocalizedString("waiting", comment: "system info"), role: .system, new: true, status: .initial))
        var appendIndex = false
        let stream = try await service.streamMessage(queryManager.query)
        for try await result in stream {
            let content = result.delta?.text ?? ""
            if !content.isEmpty {
                if !appendIndex {
                    index += 1
                    appendIndex = true
                }
                completion(index, ResponseMessage(message: content, role: .assistant, new: assistantMessage.isEmpty, status: .updating))
                assistantMessage += content
            }

            thinking += result.delta?.thinking ?? ""
            signature += result.delta?.signature ?? ""

            switch result.streamEvent {
                case .contentBlockStart:
                    if let toolUse = result.contentBlock?.toolUse {
                        toolUseList.append(ToolUse(id: toolUse.id, name: toolUse.name, input: ""))
                        toolParameters = ""
                        lastToolUseBlockIndex = result.index!
                    }
                case .contentBlockDelta:
                    if lastToolUseBlockIndex == result.index! {
                        toolParameters += result.delta?.partialJson ?? ""
                    }
                case .contentBlockStop:
                    if lastToolUseBlockIndex == result.index! {
                        var toolUse = toolUseList.last!
                        toolUse.input = jsonify(toolParameters)
                        toolUseList[toolUseList.count - 1] = toolUse
                    }
                default:
                    break
            }
        }

        if !assistantMessage.isEmpty {
            completion(index, ResponseMessage(message: "", role: .assistant, new: false, status: .finished))
        }

        var contents = [MessageParameter.Message.Content.ContentObject]()
        contents.append(.text(assistantMessage))
        if !thinking.isEmpty {
            contents.append(.thinking(thinking, signature))
        }

        // Encapsulate tool calls into query records
        for tool in toolUseList {
            let input = try JSONDecoder().decode(SwiftAnthropic.MessageResponse.Content.Input.self, from: tool.input.data(using: .utf8)!)
            contents.append(.toolUse(tool.id, tool.name, input))
        }
        queryManager.update(with: .init(role: .assistant, content: .list(contents)))

        // Call tools and append tool results to query records
        if let functions = tools, !toolUseList.isEmpty {
            let toolMessages = try await ToolsManager.callTools(index: &index, toolUseList: toolUseList, with: functions, options: options, completion: completion)
            if !toolMessages.isEmpty {
                queryManager.update(with: toolMessages)
            }
        }
    }
}

let ClaudeWordTrans = ClaudeService(prompt: "Translate the following word to Chinese, explaining its different meanings in detail, and providing examples in the original language with translations. Use markdown format for the reply, with the word as the first line title. The word is: {selected.text}")

let ClaudeTrans2Chinese = ClaudeService(prompt:"You are a professional translator proficient in Simplified Chinese. Translate the following content into Chinese. Rule: reply with the translated content directly. The content is: {selected.text}")

let ClaudeTrans2English = ClaudeService(prompt:"You are a professional translator proficient in English. Translate the following content into English. Rule: reply with the translated content directly. The content is: {selected.text}")


let svgToolClaudeDef = MessageParameter.Tool.function(
    name: "display_svg",
    description: "When user requests you to create an SVG, you can use this tool to display the SVG.",
    inputSchema: .init(type: .object, properties:[
        "raw": .init(type: .string, description: "SVG content")
    ])
)
