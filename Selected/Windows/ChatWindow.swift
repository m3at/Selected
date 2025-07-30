//
//  ChatWindow.swift
//  Selected
//
//  Created by sake on 2024/8/14.
//

import Foundation
import SwiftUI


class ChatWindowManager {
    static let shared = ChatWindowManager()

    private var lock = NSLock()
    private var windowCtrs = [ChatWindowController]()

    func closeAllWindows(_ mode: CloseWindowMode) {
        lock.lock()
        defer {lock.unlock()}

        for index in (0..<windowCtrs.count).reversed() {
            if closeWindow(mode, windowCtr: windowCtrs[index]) {
                windowCtrs.remove(at: index)
            }
        }
    }

    func createChatWindow(chatService: AIChatService, withContext ctx: ChatContext) {
        let windowController = ChatWindowController(chatService: chatService, withContext: ctx)
        closeAllWindows(.force)

        lock.lock()
        windowCtrs.append(windowController)
        lock.unlock()

        windowController.showWindow(nil)
        // If you need to handle window close events, you can add a notification observer
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: windowController.window, queue: nil) { _ in
        }
    }

    private func closeWindow(_ mode: CloseWindowMode, windowCtr: ChatWindowController) -> Bool {
        if windowCtr.pinnedModel.pinned {
            return false
        }

        switch mode {
            case .expanded:
                let frame =  windowCtr.window!.frame
                let expandedFrame = NSRect(x: frame.origin.x - kExpandedLength,
                                           y: frame.origin.y - kExpandedLength,
                                           width: frame.size.width + kExpandedLength * 2,
                                           height: frame.size.height + kExpandedLength * 2)
                if !expandedFrame.contains(NSEvent.mouseLocation){
                    windowCtr.close()
                    return true
                }

            case .original:
                let frame =  windowCtr.window!.frame
                if !frame.contains(NSEvent.mouseLocation){
                    windowCtr.close()
                    return true
                }

            case .force:
                windowCtr.close()
                return true
        }
        return false
    }

}

private class ChatWindowController: NSWindowController, NSWindowDelegate {
    var resultWindow: Bool
    var onClose: (()->Void)?

    var pinnedModel: PinnedModel

    init(chatService: AIChatService, withContext ctx: ChatContext) {
        var window: NSWindow
        // Must use NSPanel with .nonactivatingPanel and level set to .screenSaver
        // to ensure it floats above full-screen applications.
        window = FloatingPanel(
            contentRect: .zero,
            backing: .buffered,
            defer: false,
            key: true
        )

        window.alphaValue = 0.9
        self.resultWindow = true
        pinnedModel = PinnedModel()

        super.init(window: window)

        let view = ChatTextView(ctx: ctx, viewModel: MessageViewModel(chatService: chatService)).environmentObject(pinnedModel)
        window.level = .screenSaver
        window.contentView = NSHostingView(rootView: AnyView(view))
        window.delegate = self // Set delegate to self to listen for window events
        _ = ChatWindowPositionManager.shared.restorePosition(for: window)
    }

    private func positionWindow() {
        guard let window = self.window else { return }

        if ChatWindowPositionManager.shared.restorePosition(for: window) {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return
        }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        let x = (screenFrame.width - windowFrame.width) / 2 + screenFrame.origin.x
        let y = (screenFrame.height - windowFrame.height) * 3 / 4 + screenFrame.origin.y

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowDidResignActive(_ notification: Notification) {
        self.close() // Close if needed
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            ChatWindowPositionManager.shared.storePosition(of: window)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            ChatWindowPositionManager.shared.storePosition(of: window)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.async{
            self.positionWindow()
        }
    }
}

private class ChatWindowPositionManager: @unchecked Sendable {
    static let shared = ChatWindowPositionManager()

    func storePosition(of window: NSWindow) {
        Task {
            await MainActor.run {
                let frameString = NSStringFromRect(window.frame)
                UserDefaults.standard.set(frameString, forKey: "ChatWindowPosition")
            }
        }
    }

    @MainActor func restorePosition(for window: NSWindow) -> Bool {
        if let frameString = UserDefaults.standard.string(forKey: "ChatWindowPosition") {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
            return true
        }
        return false
    }
}

class PinnedModel: ObservableObject {
    @Published var pinned: Bool = false
}
