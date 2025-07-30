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
                    let OpenAIWordTrans = OpenAIService(prompt: "Translate the following word to Chinese, explaining its different meanings in detail, and providing examples in the original language with translations. Use markdown format for the reply, with the word as the first line title. The word is: {selected.text}", model: Defaults[.openAITranslationModel])
                    await OpenAIWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    let OpenAITrans2Chinese = OpenAIService(prompt:"You are a professional translator proficient in Simplified Chinese. Translate the following content into Chinese. Rule: reply with the translated content directly. The content is: {selected.text}", model: Defaults[.openAITranslationModel])
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
                let OpenAITrans2English = OpenAIService(prompt:"You are a professional translator proficient in English. Translate the following content into English. Rule: reply with the translated content directly. The content is：{selected.text}", model: Defaults[.openAITranslationModel])
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
    parameters: .init(
        fields: [
            .type( .object),
            .properties(
                [
                    "raw": .init(
                        fields: [
                            .type(.string), .description("SVG content")
                        ])
                ])
        ])
)



struct SVGData: Codable, Equatable {
    public let raw: String
}

// Input is raw SVG data, save it to a temporary file and open it with the default browser.
func openSVGInBrowser(svgData: String) -> Bool {
    do {
        let data = try JSONDecoder().decode(SVGData.self, from: svgData.data(using: .utf8)!)

        // Create temporary file path
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("temp_svg_\(UUID().uuidString).svg")

        // Write SVG data to the temporary file
        try data.raw.write(to: tempFile, atomically: true, encoding: .utf8)

        // Open the file with the default browser
        DispatchQueue.global().async {
            NSWorkspace.shared.open(tempFile)
        }
        return true
    } catch {
        print("Error opening SVG file: \(error.localizedDescription)")
        return false
    }
}

let MAX_CHAT_ROUNDS = 20
