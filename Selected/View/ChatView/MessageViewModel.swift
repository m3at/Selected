//
//  MessageViewModel.swift
//  Selected
//
//  Created by sake on 2024/6/29.
//

import Foundation

@MainActor
class MessageViewModel: ObservableObject {
    @Published var messages: [ResponseMessage] = []
    var chatService: AIChatService

    init(chatService: AIChatService) {
        self.chatService = chatService
        self.messages.append(ResponseMessage(message: NSLocalizedString("waiting", comment: "system info"), role: .system))
    }

    func submit(message: String) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await MainActor.run {
                    self.messages.append(ResponseMessage(message: message, role: .user, status: .finished))
                }
            }
        }
        await chatService.chatFollow(index: messages.count-1, userMessage: message){ [weak self]  index, message in
            DispatchQueue.main.async {
                [weak self] in
                guard let self = self else { return }
                if self.messages.count < index+1 {
                    self.messages.append(ResponseMessage(message: "", role:  message.role))
                }
                if message.role != self.messages[index].role {
                    self.messages[index].role = message.role
                }
                self.messages[index].status = message.status
                if message.new {
                    self.messages[index].message = message.message
                } else {
                    self.messages[index].message += message.message
                }
            }
        }
    }

    func fetchMessages(ctx: ChatContext) async -> Void{
        await chatService.chat(ctx: ctx) { [weak self]  index, message in
            DispatchQueue.main.async {
                [weak self] in
                guard let self = self else { return }
                if self.messages.count < index+1 {
                    self.messages.append(ResponseMessage(message: "", role:  message.role))
                }

                if message.role != self.messages[index].role {
                    self.messages[index].role = message.role
                }

                self.messages[index].status = message.status
                if message.new {
                    self.messages[index].message = message.message
                } else {
                    self.messages[index].message += message.message
                }
            }
        }
    }
}
