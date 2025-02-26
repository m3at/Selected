//
//  AI.swift
//  Selected
//
//  Created by sake on 2024/3/10.
//

import Defaults
import SwiftUI
import OpenAI

public struct ChatContext {
    let text: String
    let webPageURL: String
    let bundleID: String
}

func isWord(str: String) -> Bool {
    for c in str {
        if c.isLetter || c == "-" {
            continue
        }
        return false
    }
    return true
}

struct Translation {
    let toLanguage: String
    
    func translate(content: String, completion: @escaping (_: String) -> Void)  async -> Void{
        if toLanguage == "cn" {
            await contentTrans2Chinese(content: content, completion: completion)
        } else if toLanguage == "en" {
            await contentTrans2English(content: content, completion: completion)
        }
    }
    
    private func isWord(str: String) -> Bool {
        for c in str {
            if c.isLetter || c == "-" {
                continue
            }
            return false
        }
        return true
    }
    
    private func contentTrans2Chinese(content: String, completion: @escaping (_: String) -> Void)  async -> Void{
        switch Defaults[.aiService] {
            case "OpenAI":
                if isWord(str: content) {
                    let OpenAIWordTrans = OpenAIPrompt(prompt: "翻译以下单词到中文，详细说明单词的不同意思，并且给出原语言的例句与翻译。使用 markdown 的格式回复，要求第一行标题为单词。单词为：{selected.text}", model: Defaults[.openAITranslationModel])
                    await OpenAIWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    let OpenAITrans2Chinese = OpenAIPrompt(prompt:"你是一位精通简体中文的专业翻译。翻译指定的内容到中文。规则：请直接回复翻译后的内容。内容为：{selected.text}", model: Defaults[.openAITranslationModel])
                    await OpenAITrans2Chinese.chatOne(selectedText: content, completion: completion)
                }
            case "Claude":
                if isWord(str: content) {
                    await ClaudeWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    await ClaudeTrans2Chinese.chatOne(selectedText: content, completion: completion)
                }
            default:
                completion("no model \(Defaults[.aiService])")
        }
    }
    
    private func contentTrans2English(content: String, completion: @escaping (_: String) -> Void)  async -> Void{
        switch Defaults[.aiService] {
            case "OpenAI":
                let OpenAITrans2English = OpenAIPrompt(prompt:"You are a professional translator proficient in English. Translate the following content into English. Rule: reply with the translated content directly. The content is：{selected.text}", model: Defaults[.openAITranslationModel])
                await OpenAITrans2English.chatOne(selectedText: content, completion: completion)
            case "Claude":
                await ClaudeTrans2English.chatOne(selectedText: content, completion: completion)
            default:
                completion("no model \(Defaults[.aiService])")
        }
    }
    
    private func convert(index: Int, message: ResponseMessage)->Void {
        
    }
}

struct ChatService: AIChatService{
    var chatService: AIChatService
    
    init?(prompt: String, options: [String:String]){
        switch Defaults[.aiService] {
            case "OpenAI":
                chatService = OpenAIService(prompt: prompt, options: options)
            case "Claude":
                chatService = ClaudeService(prompt: prompt, options: options)
            default:
                return nil
        }
    }
    
    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void{
        await chatService.chat(ctx: ctx, completion: completion)
    }
    
    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
            await chatService.chatFollow(index: index, userMessage: userMessage, completion: completion)
        }
}


class OpenAIService: AIChatService{
    var openAI: OpenAIPrompt
    
    init(prompt: String, tools: [FunctionDefinition]? = nil, options: [String:String]) {
        var fcs = [FunctionDefinition]()
        if let tools = tools {
            fcs.append(contentsOf: tools)
        }
        openAI = OpenAIPrompt(prompt: prompt, tools: fcs,  options: options)
    }
    
    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void{
        await openAI
            .chat(ctx: ctx, completion: completion)
    }
    
    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
            await openAI
                .chatFollow(index: index, userMessage: userMessage, completion: completion)
        }
}


public protocol AIChatService {
    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void
    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void
}


public class ResponseMessage: ObservableObject, Identifiable, Equatable{
    public static func == (lhs: ResponseMessage, rhs: ResponseMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    public enum Status: String {
        case initial, updating, finished, failure
    }
    
    public enum Role: String {
        case assistant, tool, user, system
    }
    
    public var id = UUID()
    @Published var message: String
    @Published var role: Role
    @Published var status: Status
    var new: Bool = false // new start of message
    
    init(id: UUID = UUID(), message: String, role: Role, new: Bool = false, status: Status = .initial) {
        self.id = id
        self.message = message
        self.role = role
        self.new = new
        self.status = status
    }
}


func systemPrompt() -> String{
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale.current
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let localDate = dateFormatter.string(from: Date())
    
    let language = getCurrentAppLanguage()
    var currentLocation = ""
    if let location = LocationManager.shared.place {
        currentLocation = "I'm at \(location)"
    }
    return """
                      Current time is \(localDate).
                      \(currentLocation)
                      You are a tool running on macOS called Selected. You can help user do anything.
                      The system language is \(language), you should try to reply in \(language) as much as possible, unless the user specifies to use another language, such as specifying to translate into a certain language.
                      """
}


let svgToolOpenAIDef = ChatQuery.ChatCompletionToolParam.FunctionDefinition(
    name: "svg_dispaly",
    description: "When user requests you to create an SVG, you can use this tool to display the SVG.",
    parameters: .init(type: .object, properties:[
        "raw": .init(type: .string, description: "SVG content")
    ])
)



struct SVGData: Codable, Equatable {
    public let raw: String
}

// 输入为 svg 的原始数据，要求保存到一个临时文件里，然后通过默认浏览器打开这个文件。
func openSVGInBrowser(svgData: String) -> Bool {
    do {
        let data = try JSONDecoder().decode(SVGData.self, from: svgData.data(using: .utf8)!)
        
        // 创建临时文件路径
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("temp_svg_\(UUID().uuidString).svg")
        
        // 将 SVG 数据写入临时文件
        try data.raw.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // 使用默认浏览器打开文件
        DispatchQueue.global().async {
            NSWorkspace.shared.open(tempFile)
        }
        return true
    } catch {
        print("打开 SVG 文件时发生错误: \(error.localizedDescription)")
        return false
    }
}

let MAX_CHAT_ROUNDS = 20
