//
//  OpenAI.swift
//  Selected
//
//  Created by sake on 2024/3/10.
//

import OpenAI
import Defaults
import SwiftUI
import AVFoundation

typealias OpenAIModel = Model

let OpenAIModels: [Model] = [.gpt4_o, .gpt4_o_mini, .o1, .o1_mini, .o3_mini, .gpt4_turbo]


struct FunctionDefinition: Codable, Equatable{
    /// The name of the function to be called. Must be a-z, A-Z, 0-9, or contain underscores and dashes, with a maximum length of 64.
    public let name: String

    /// The description of what the function does.
    public let description: String
    /// The parameters the functions accepts, described as a JSON Schema object. See the guide for examples, and the JSON Schema reference for documentation about the format.
    /// Omitting parameters defines a function with an empty parameter list.
    public let parameters: String

    /// The command to execute
    public var command: [String]?
    /// In which dir to execute command.
    public var workdir: String?
    public var showResult: Bool? = true
    public var template: String?

    func Run(arguments: String, options: [String:String] = [String:String]()) throws -> String? {
        guard let command = self.command else {
            return nil
        }
        var args = [String](command[1...])
        args.append(arguments)

        var env = [String:String]()
        options.forEach{ (key: String, value: String) in
            env["SELECTED_OPTIONS_"+key.uppercased()] = value
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:" + path
        }
        return try executeCommand(workdir: workdir!, command: command[0], arguments: args, withEnv: env)
    }

    func getParameters() -> FunctionParameters?{
        let p = try! JSONDecoder().decode(FunctionParameters.self, from: self.parameters.data(using: .utf8)!)
        return p
    }
}

let dalle3Def = ChatQuery.ChatCompletionToolParam.FunctionDefinition(
    name: "Dall-E-3",
    description: "When user asks for a picture, create a prompt that dalle can use to generate the image. The prompt must be in English. Translate to English if needed. The url of the image will be returned.",
    parameters: .init(type: .object, properties:[
        "prompt": .init(type: .string, description: "the generated prompt sent to dalle3")
    ])
)


typealias OpenAIChatCompletionMessageToolCallParam = ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam
typealias ChatFunctionCall = OpenAIChatCompletionMessageToolCallParam.FunctionCall
typealias FunctionParameters = ChatQuery.ChatCompletionToolParam.FunctionDefinition.FunctionParameters


struct OpenAIPrompt {
    let prompt: String
    var tools: [FunctionDefinition]?
    let openAI: OpenAI
    var query: ChatQuery
    var options: [String:String]

    init(prompt: String, tools: [FunctionDefinition]? = nil, options: [String:String] = [String:String]()) {
        self.prompt = prompt
        self.tools = tools
        var host = "api.openai.com"
        if Defaults[.openAIAPIHost] != "" {
            host = Defaults[.openAIAPIHost]
        }
        let configuration = OpenAI.Configuration(token: Defaults[.openAIAPIKey] , host: host, timeoutInterval: 60.0)
        self.openAI = OpenAI(configuration: configuration)
        self.options = options
        self.query = OpenAIPrompt.createQuery(functions: tools)
    }


    func chatOne(
        selectedText: String,
        completion: @escaping (_: String) -> Void) async -> Void {
            var messages = query.messages
            let message = replaceOptions(content: prompt, selectedText: selectedText, options: options)
            messages.append(.init(role: .user, content: message)!)
            let query = ChatQuery(
                messages: messages,
                model: Defaults[.openAIModel],
                tools: query.tools
            )

            do {
                for try await result in openAI.chatsStream(query: query) {
                    if result.choices[0].finishReason == nil && result.choices[0].delta.content != nil {
                        completion(result.choices[0].delta.content!)
                    }
                }
            } catch {
                NSLog("completion error \(String(describing: error))")
                return
            }

        }

    private static func createQuery(functions: [FunctionDefinition]?) -> ChatQuery {
        var tools: [ChatQuery.ChatCompletionToolParam]? = nil
        if let functions = functions {
            var _tools: [ChatQuery.ChatCompletionToolParam] = [.init(function: dalle3Def)]
            for fc in functions {
                let fc = ChatQuery.ChatCompletionToolParam.FunctionDefinition(
                    name: fc.name,
                    description: fc.description,
                    parameters: fc.getParameters()
                )
                _tools.append(.init(function: fc))
            }
            tools = _tools
        }

        if Defaults[.openAIModel] == "o1-preview" {
            return ChatQuery(
                messages: [],
                model: Defaults[.openAIModel],
                tools: nil
            )
        }

        // 通过 Swift 获取当前应用的语言
        return ChatQuery(
            messages: [
                .init(role: .developer, content: systemPrompt())!],
            model: Defaults[.openAIModel],
            tools: tools
        )
    }

    mutating func updateQuery(message: ChatQuery.ChatCompletionMessageParam) {
        var messages = query.messages
        messages.append(message)
        query = ChatQuery(
            messages: messages,
            model: Defaults[.openAIModel],
            tools: query.tools
        )
    }

    mutating func updateQuery(messages: [ChatQuery.ChatCompletionMessageParam]) {
        var _messages = query.messages
        _messages.append(contentsOf: messages)
        query = ChatQuery(
            messages: _messages,
            model: Defaults[.openAIModel],
            tools: query.tools
        )
    }

    mutating func chat(
        ctx: ChatContext,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
            var message = renderChatContent(content: prompt, chatCtx: ctx, options: options)
            message = replaceOptions(content: message, selectedText: ctx.text, options: options)
            updateQuery(message: .init(role: .user, content: message)!)

            var index = -1
            while let last = query.messages.last, last.role != .assistant {
                do {
                    try await chatOneRound(index: &index, completion: completion)
                } catch {
                    index += 1
                    let localMsg = String(format: NSLocalizedString("error_exception", comment: "system info"), error as CVarArg)
                    NSLog(localMsg)
                    let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                    completion(index, message)
                    return
                }
                if index >= 10 {
                    index += 1
                    let localMsg = NSLocalizedString("Too much rounds, please start a new chat", comment: "system info")
                    let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                    completion(index, message)
                    return
                }
            }
        }

    mutating func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
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
                if newIndex-index >= 10 {
                    newIndex += 1
                    let localMsg = NSLocalizedString("Too much rounds, please start a new chat", comment: "system info")
                    let message = ResponseMessage(message: localMsg, role: .system, new: true, status: .failure)
                    completion(newIndex, message)
                    return
                }
            }
        }

    mutating func chatOneRound(
        index: inout Int,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async throws -> Void {
            NSLog("index is \(index)")
            var hasTools = false
            var toolCallsDict = [Int: ChatCompletionMessageToolCallParam]()
            var hasMessage =  false
            var assistantMessage = ""

            completion(index+1, ResponseMessage(message: NSLocalizedString("Waiting", comment: "system info"), role: .system, new: true, status: .initial))
            for try await result in openAI.chatsStream(query: query) {
                if let toolCalls = result.choices[0].delta.toolCalls {
                    hasTools = true
                    for f in toolCalls {
                        let toolCallID = f.index
                        if let toolCall = toolCallsDict[toolCallID] {
                            let newToolCall =  ChatCompletionMessageToolCallParam(id: toolCall.id, function: .init(arguments: toolCall.function.arguments + f.function!.arguments!, name: toolCall.function.name))
                            toolCallsDict[toolCallID] = newToolCall
                        } else {
                            let toolCall = ChatCompletionMessageToolCallParam(id: f.id!, function: .init(arguments: f.function!.arguments!, name: f.function!.name!))
                            toolCallsDict[toolCallID] = toolCall
                        }
                    }
                }

                if result.choices[0].finishReason == nil && result.choices[0].delta.content != nil {
                    var newMessage = false
                    if !hasMessage {
                        index += 1
                        hasMessage = true
                        newMessage = true
                    }
                    let message = ResponseMessage(message: result.choices[0].delta.content!, role: .assistant, new: newMessage, status: .updating)
                    assistantMessage += message.message
                    completion(index, message)
                }
            }

            if hasMessage {
                completion(index, ResponseMessage(message: "", role: .assistant, new: false, status: .finished))
            }
            if !hasTools {
                updateQuery(message: .assistant(.init(content:assistantMessage)))
                return
            }

            var toolCalls  =  [OpenAIChatCompletionMessageToolCallParam]()
            for (_, tool) in toolCallsDict {
                let function =
                try JSONDecoder().decode(ChatFunctionCall.self, from: JSONEncoder().encode(tool.function))
                toolCalls.append(.init(id: tool.id, function: function))
            }
            updateQuery(message: .assistant(.init(content:assistantMessage, toolCalls: toolCalls)))

            let toolMessages = try await callTools(index: &index, toolCallsDict: toolCallsDict, completion: completion)
            if toolMessages.isEmpty {
                return
            }
            updateQuery(messages: toolMessages)
        }

    private func callTools(
        index: inout Int,
        toolCallsDict: [Int: ChatCompletionMessageToolCallParam],
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async throws -> [ChatQuery.ChatCompletionMessageParam] {
            guard let fcs = tools else {
                return []
            }

            index += 1
            NSLog("tool index \(index)")

            var fcSet = [String: FunctionDefinition]()
            for fc in fcs {
                fcSet[fc.name] = fc
            }

            var messages = [ChatQuery.ChatCompletionMessageParam]()
            for (_, tool) in toolCallsDict {
                let rawMessage = String(format: NSLocalizedString("calling_tool", comment: "tool message"), tool.function.name)
                let message =  ResponseMessage(message: rawMessage, role: .tool, new: true, status: .updating)

                if let f = fcSet[tool.function.name] {
                    if let template = f.template {
                        message.message =  renderTemplate(templateString: template, json: tool.function.arguments)
                        NSLog("\(message.message)")
                    }
                }
                completion(index, message)
                NSLog("\(tool.function.arguments)")
                if tool.function.name == dalle3Def.name {
                    let url = try await dalle3(openAI: openAI, arguments: tool.function.arguments)
                    messages.append(.tool(.init(content: url, toolCallId: tool.id)))
                    let ret = "[![this is picture]("+url+")]("+url+")"
                    let message = ResponseMessage(message: ret, role: .tool, new: true, status: .finished)
                    completion(index, message)
                } else  {
                    if let f = fcSet[tool.function.name] {
                        NSLog("call: \(tool.function.arguments)")
                        if let ret = try f.Run(arguments: tool.function.arguments, options: options) {
                            let message = ResponseMessage(message: ret, role: .tool, new: true, status: .finished)
                            if let show = f.showResult, !show {
                                if f.template != nil {
                                    message.message = ""
                                    message.new = false
                                } else {
                                    message.message = String(format: NSLocalizedString("called_tool", comment: "tool message"), f.name)
                                }
                            }
                            completion(index, message)
                            messages.append(.tool(.init(content: ret, toolCallId: tool.id)))
                        }
                    }
                }
            }
            return messages
        }
}

private func dalle3(openAI: OpenAI, arguments: String) async throws -> String {
    var content =  ""

    let prompt = try JSONDecoder().decode(Dalle3Prompt.self, from: arguments.data(using: .utf8)!)
    let imageQuery = ImagesQuery(
        prompt: prompt.prompt,
        model: .dall_e_3)
    let res = try await openAI.images(query: imageQuery)
    content = res.data[0].url!
    NSLog("image URL: %@", content)
    return content
}

let OpenAIWordTrans = OpenAIPrompt(prompt: "翻译以下单词到中文，详细说明单词的不同意思，并且给出原语言的例句与翻译。使用 markdown 的格式回复，要求第一行标题为单词。单词为：{selected.text}")

let OpenAITrans2Chinese = OpenAIPrompt(prompt:"你是一位精通简体中文的专业翻译。翻译指定的内容到中文。规则：请直接回复翻译后的内容。内容为：{selected.text}")

let OpenAITrans2English = OpenAIPrompt(prompt:"You are a professional translator proficient in English. Translate the following content into English. Rule: reply with the translated content directly. The content is：{selected.text}")

internal var audioPlayer: AVAudioPlayer?

private struct VoiceData {
    var data: Data
    var lastAccessTime: Date
}

private var voiceDataCache = [Int: VoiceData]()

// TODO: regular cleaning
private func clearExpiredVoiceData() {
    for (k, v) in voiceDataCache {
        if v.lastAccessTime.addingTimeInterval(120) < Date() {
            voiceDataCache.removeValue(forKey: k)
        }
    }
}

func openAITTS(_ text: String) async {
    clearExpiredVoiceData()
    if let data = voiceDataCache[text.hash] {
        NSLog("cached tts")
        audioPlayer?.stop()
        audioPlayer = try! AVAudioPlayer(data: data.data)
        audioPlayer!.play()
        return
    }

    let configuration = OpenAI.Configuration(token: Defaults[.openAIAPIKey] , host: Defaults[.openAIAPIHost] , timeoutInterval: 60.0)
    let openAI = OpenAI(configuration: configuration)
    let query = AudioSpeechQuery(model: .tts_1, input: text, voice: Defaults[.openAIVoice], responseFormat: .mp3, speed: 1.0)

    do {
        let result = try await openAI.audioCreateSpeech(query: query)
        voiceDataCache[text.hash] = VoiceData(data: result.audio , lastAccessTime: Date())
        audioPlayer?.stop()
        audioPlayer = try! AVAudioPlayer(data:  result.audio)
        audioPlayer!.play()
    } catch {
        NSLog("audioCreateSpeech \(error)")
        return
    }
}

func openAITTS2(_ text: String) async -> Data? {
    clearExpiredVoiceData()
    if let data = voiceDataCache[text.hash] {
        NSLog("cached tts")
        return data.data
    }

    let configuration = OpenAI.Configuration(token: Defaults[.openAIAPIKey] , host: Defaults[.openAIAPIHost] , timeoutInterval: 60.0)
    let openAI = OpenAI(configuration: configuration)
    let query = AudioSpeechQuery(model: .tts_1, input: text, voice: Defaults[.openAIVoice], responseFormat: .mp3, speed: 1.0)

    do {
        let result = try await openAI.audioCreateSpeech(query: query)
        voiceDataCache[text.hash] = VoiceData(data: result.audio , lastAccessTime: Date())
        return result.audio
    } catch {
        NSLog("audioCreateSpeech \(error)")
        return nil
    }
}

typealias ChatCompletionMessageToolCallParam = OpenAIChatCompletionMessageToolCallParam


struct Dalle3Prompt: Codable, Equatable {
    /// The ID of the tool call.
    public let prompt: String
}

