//
//  LocalModelService.swift
//  Selected
//
//  Created by Selected on 2025/07/30.
//

import Foundation
import Defaults
import OpenAI

class LocalModelService: AIChatService {
    private let prompt: String
    private var tools: [FunctionDefinition]?
    private let openAI: OpenAI
    private var query: ChatQuery
    private var options: [String: String]

    init(prompt: String, tools: [FunctionDefinition]? = nil, options: [String: String] = [:]) {
        self.prompt = prompt
        self.tools = tools
        let port = Defaults[.localModelPort]
        let host = "localhost:\(port)"
        let configuration = OpenAI.Configuration(token: "local", host: host, scheme: "http", timeoutInterval: 60.0, parsingOptions:
.relaxed)
        self.openAI = OpenAI(configuration: configuration)
        self.options = options
        self.query = LocalModelService.createQuery(functions: tools, model: Defaults[.localModel])
    }

    init(prompt: String, model: String) {
        self.prompt = prompt
        self.tools = nil
        let port = Defaults[.localModelPort]
        let host = "localhost:\(port)"
        let configuration = OpenAI.Configuration(token: "local", host: host, scheme: "http", timeoutInterval: 60.0)
        self.openAI = OpenAI(configuration: configuration)
        self.options = [:]
        self.query = LocalModelService.createQuery(functions: tools, model: model)
    }

    private func updateQuery(message: ChatQuery.ChatCompletionMessageParam) {
        var messages = query.messages
        messages.append(message)
        query = ChatQuery(messages: messages, model: query.model, tools: query.tools)
    }

    private func updateQuery(messages: [ChatQuery.ChatCompletionMessageParam]) {
        var updatedMessages = query.messages
        updatedMessages.append(contentsOf: messages)
        query = ChatQuery(messages: updatedMessages, model: query.model, tools: query.tools)
    }

    func chatOne(selectedText: String, completion: @escaping (String) -> Void) async {
        var messages = query.messages
        let messageContent = replaceOptions(content: prompt, selectedText: selectedText, options: options)
        messages.append(.init(role: .user, content: messageContent)!)
        let query = ChatQuery(messages: messages, model: query.model, tools: query.tools)

        do {
            for try await result in openAI.chatsStream(query: query) {
                if result.choices[0].finishReason == nil, let content = result.choices[0].delta.content {
                    completion(content)
                }
            }
        } catch {
            print("completion error \(error)")
        }
    }

    func chat(ctx: ChatContext, completion: @escaping (Int, ResponseMessage) -> Void) async {
        var messageContent = renderChatContent(content: prompt, chatCtx: ctx, options: options)
        messageContent = replaceOptions(content: messageContent, selectedText: ctx.text, options: options)
        updateQuery(message: .init(role: .user, content: messageContent)!)

        var index = -1
        while let last = query.messages.last, last.role != .assistant {
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

    func chatFollow(index: Int, userMessage: String, completion: @escaping (Int, ResponseMessage) -> Void) async {
        updateQuery(message: .init(role: .user, content: userMessage)!)
        var newIndex = index
        while let last = query.messages.last, last.role != .assistant {
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

    private func chatOneRound(index: inout Int, completion: @escaping (Int, ResponseMessage) -> Void) async throws {
        var hasTools = false
        var toolCallsDict = [Int: OpenAIChatCompletionMessageToolCallParam]()
        var hasMessage = false
        var assistantMessage = ""

        completion(index + 1, ResponseMessage(message: NSLocalizedString("Waiting", comment: "system info"), role: .system, new: true,
status: .initial))
        for try await result in openAI.chatsStream(query: query) {
            if let toolCalls = result.choices[0].delta.toolCalls {
                hasTools = true
                for f in toolCalls {
                    let toolCallID = f.index
                    if let existing = toolCallsDict[toolCallID] {
                        let newToolCall = OpenAIChatCompletionMessageToolCallParam(
                            id: existing.id,
                            function: .init(
                                arguments: existing.function.arguments + (f.function?.arguments ?? ""),
                                name: existing.function.name
                            )
                        )
                        toolCallsDict[toolCallID] = newToolCall
                    } else {
                        let toolCall = OpenAIChatCompletionMessageToolCallParam(
                            id: f.id!,
                            function: .init(
                                arguments: f.function?.arguments ?? "",
                                name: f.function?.name ?? ""
                            )
                        )
                        toolCallsDict[toolCallID] = toolCall
                    }
                }
            }

            if result.choices[0].finishReason == nil, let content = result.choices[0].delta.content {
                var newMessage = false
                if !hasMessage {
                    index += 1
                    hasMessage = true
                    newMessage = true
                }
                let message = ResponseMessage(message: content, role: .assistant, new: newMessage, status: .updating)
                assistantMessage += message.message
                completion(index, message)
            }
        }

        if hasMessage {
            completion(index, ResponseMessage(message: "", role: .assistant, new: false, status: .finished))
        }
        if !hasTools {
            updateQuery(message: .assistant(.init(content: assistantMessage)))
            return
        }

        var toolCalls = [OpenAIChatCompletionMessageToolCallParam]()
        for (_, tool) in toolCallsDict {
            let function = try JSONDecoder().decode(ChatFunctionCall.self, from: JSONEncoder().encode(tool.function))
            toolCalls.append(.init(id: tool.id, function: function))
        }
        updateQuery(message: .assistant(.init(content: assistantMessage, toolCalls: toolCalls)))

        let toolMessages = try await callTools(index: &index, toolCallsDict: toolCallsDict, completion: completion)
        if !toolMessages.isEmpty {
            updateQuery(messages: toolMessages)
        }
    }

    private func callTools(index: inout Int, toolCallsDict: [Int: OpenAIChatCompletionMessageToolCallParam], completion: @escaping (Int,
ResponseMessage) -> Void) async throws -> [ChatQuery.ChatCompletionMessageParam] {
        guard let functions = tools else { return [] }

        index += 1
        print("tool index \(index)")

        var functionMap = [String: FunctionDefinition]()
        for function in functions {
            functionMap[function.name] = function
        }

        var messages = [ChatQuery.ChatCompletionMessageParam]()
        for (_, tool) in toolCallsDict {
            let toolMessage = ResponseMessage(
                message: String(format: NSLocalizedString("calling_tool", comment: "tool message"), tool.function.name),
                role: .tool,
                new: true,
                status: .updating
            )
            if let funcDef = functionMap[tool.function.name],
               let template = funcDef.template {
                toolMessage.message = renderTemplate(templateString: template, json: tool.function.arguments)
                print("\(toolMessage.message)")
            }
            completion(index, toolMessage)
            print("\(tool.function.arguments)")

            if tool.function.name == dalle3Def.name {
                let url = try await ImageGeneration.generateDalle3Image(openAI: openAI, arguments: tool.function.arguments)
                messages.append(.tool(.init(content: url, toolCallId: tool.id)))
                let ret = "[![this is picture](" + url + ")](" + url + ")"
                let message = ResponseMessage(message: ret, role: .tool, new: true, status: .finished)
                completion(index, message)
            } else if tool.function.name == svgToolOpenAIDef.name {
                _ = openSVGInBrowser(svgData: tool.function.arguments)
                messages.append(.tool(.init(content: "display svg successfully", toolCallId: tool.id)))
                let message = ResponseMessage(message: NSLocalizedString("display_svg", comment: ""), role: .tool, new: true, status:
.finished)
                completion(index, message)
            } else {
                if let funcDef = functionMap[tool.function.name] {
                    print("call: \(tool.function.arguments)")
                    if let ret = try funcDef.Run(arguments: tool.function.arguments, options: options) {
                        let statusMessage = (funcDef.showResult ?? true)
                        ? ret
                        : String(format: NSLocalizedString("called_tool", comment: "tool message"), funcDef.name)
                        let message = ResponseMessage(message: statusMessage, role: .tool, new: true, status: .finished)
                        completion(index, message)
                        messages.append(.tool(.init(content: ret, toolCallId: tool.id)))
                    }
                }
            }
        }
        return messages
    }

    private static func createQuery(functions: [FunctionDefinition]?, model: String) -> ChatQuery {
        var tools: [ChatQuery.ChatCompletionToolParam]? = nil
        if let functions = functions {
            var toolList: [ChatQuery.ChatCompletionToolParam] = [.init(function: dalle3Def), .init(function: svgToolOpenAIDef)]
            for fc in functions {
                let fcConverted = ChatQuery.ChatCompletionToolParam.FunctionDefinition(
                    name: fc.name,
                    description: fc.description,
                    parameters: fc.getParameters()
                )
                toolList.append(.init(function: fcConverted))
            }
            tools = toolList
        }

        return ChatQuery(
            messages: [.init(role: .developer, content: systemPrompt())!],
            model: model,
            tools: tools
        )
    }
}