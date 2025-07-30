//
//  WindowManager.swift
//  Selected
//
//  Created by sake on 2024/3/18.
//

import Foundation
import SwiftUI

// MARK: - Window Type Enum
enum WindowType {
    case popBar
    case translation
    case tts
    case text
}

// MARK: - Window Position Strategy
enum WindowPositionStrategy {
    case centerScreen
    case nearMouse
    case centerScreenOffset(CGFloat) // Allows vertical offset, e.g., at 3/4 position
}

//// MARK: - Close Window Mode
enum CloseWindowMode {
    case expanded
    case original
    case force
}

// MARK: - Window Controller Protocol
protocol WindowCtr: NSObjectProtocol {
    func close()
    func frame() -> NSRect
    func showWindow(_ sender: Any?)
    func isPopbar() -> Bool
    var window: NSWindow? { get }
    var onClose: (()->Void)? { get set }
}

// MARK: - Base Window Controller
class BaseWindowController: NSWindowController, NSWindowDelegate, WindowCtr {
    var onClose: (()->Void)?
    private var windowType: WindowType

    func frame() -> NSRect {
        return window?.frame ?? .zero
    }

    func isPopbar() -> Bool {
        return windowType == .popBar
    }

    init(rootView: AnyView, windowType: WindowType,
         positionStrategy: WindowPositionStrategy,
         size: NSSize,
         isKey: Bool = false, alpha: CGFloat = 1.0) {
        self.windowType = windowType

        // Create window
        let window = FloatingPanel(
            contentRect: .init(x: 0, y: 0, width: size.width, height: size.height),
            backing: .buffered,
            defer: false,
            key: isKey
        )

        window.alphaValue = alpha
        if alpha == 1.0 {
            window.isOpaque = true
            window.backgroundColor = .clear
        }

        super.init(window: window)

        window.level = .screenSaver
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
        // Position window according to strategy
        positionWindow(using: positionStrategy, windowSize: size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func positionWindow(using strategy: WindowPositionStrategy, windowSize: NSSize) {
        guard self.window != nil else { return }

        switch strategy {
            case .centerScreen:
                centerWindowOnScreen(size: windowSize)
            case .nearMouse:
                positionWindowNearMouse()
            case .centerScreenOffset(let verticalFactor):
                centerWindowOnScreen(size: windowSize, verticalFactor: verticalFactor)
        }
    }

    private func centerWindowOnScreen(size: NSSize, verticalFactor: CGFloat = 0.5) {
        guard let window = self.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return
        }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let width = windowFrame.width == 0 ?  size.width  : windowFrame.width
        let height = windowFrame.height == 0 ? size.height : windowFrame.height

        let x = (screenFrame.width - width) / 2 + screenFrame.origin.x
        let y = (screenFrame.height - height) * verticalFactor + screenFrame.origin.y

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionWindowNearMouse() {
        guard let window = self.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return
        }

        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width

        // Ensure the window does not go beyond the screen edges
        let x = min(screenFrame.maxX - windowWidth,
                    max(mouseLocation.x - windowWidth/2, screenFrame.minX))

        var y = mouseLocation.y + 18
        if y > screenFrame.maxY {
            y = mouseLocation.y - 30 - 18
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignActive(_ notification: Notification) {
        self.close()
    }

    override func close() {
        super.close()
        onClose?()
    }
}

// MARK: - Specialized Window Controllers
class PopBarWindowController: BaseWindowController {
    init(rootView: AnyView) {
        super.init(rootView: rootView, windowType: .popBar, positionStrategy: .nearMouse, size: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TranslationWindowController: BaseWindowController {
    init(rootView: AnyView) {
        super.init(rootView: rootView, windowType: .translation, positionStrategy: .centerScreenOffset(0.75), size: .init(width: 550, height: 450), isKey: true, alpha: 0.9)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TTSWindowController: BaseWindowController {
    init(rootView: AnyView) {
        super.init(rootView: rootView, windowType: .tts, positionStrategy: .centerScreen, size: .init(width: 600, height: 150))
    }

    deinit {
        TTSManager.stopSpeak()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TextWindowController: BaseWindowController {
    init(text: String) {
        let view = PopResultView(text: text)
        super.init(rootView: AnyView(view), windowType: .text, positionStrategy: .nearMouse, size: .zero, alpha: 0.9)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Window Manager
class WindowManager {
    static let shared = WindowManager()

    // TODO: Consider using a lock to protect this variable
    private var windowCtr: WindowCtr?

    // When in showing SharingPicker, we should avoid close popbar window by accident.
    var showingSharingPicker = false

    // MARK: - Public API

    func createPopBarWindow(_ ctx: SelectedTextContext) {
        let contentView = PopBarView(actions: GetActions(ctx: ctx), ctx: ctx)
        let windowController = PopBarWindowController(rootView: AnyView(contentView))
        createWindow(windowController)
    }

    func createTranslationWindow(withText text: String, to: String) {
        let contentView = TranslationView(text: text, to: to)
        let windowController = TranslationWindowController(rootView: AnyView(contentView))
        createWindow(windowController)
    }

    func createAudioPlayerWindow(_ audio: Data) {
        guard let url = createTemporaryURLForData(audio, fileName: "selected-tmptts.mp3") else {
            return
        }

        let contentView = AudioPlayerView(audioURL: url)
        let windowController = TTSWindowController(rootView: AnyView(contentView))

        windowController.onClose = {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error removing temporary file: \(error)")
            }
        }

        createWindow(windowController)
    }

    func createTextWindow(_ text: String) {
        createWindow(TextWindowController(text: text))
    }

    func closeOnlyPopbarWindows(_ mode: CloseWindowMode) -> Bool {
        guard let windowCtr = windowCtr, !showingSharingPicker else {
            return false
        }

        if windowCtr.isPopbar() {
            return closeWindow(mode, windowCtr: windowCtr)
        }
        return false
    }

    func closeAllWindows(_ mode: CloseWindowMode) -> Bool {
        guard let windowCtr = windowCtr, !showingSharingPicker else {
            return false
        }

        return closeWindow(mode, windowCtr: windowCtr)
    }

    // MARK: - Private methods

    private func createWindow(_ windowController: WindowCtr) {
        windowCtr?.close()
        windowController.showWindow(nil)
        windowCtr = windowController

        // Add window close notification observer
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: windowController.window,
            queue: nil
        ) { [weak self] _ in
            self?.windowCtr = nil
        }
    }

    private func closeWindow(_ mode: CloseWindowMode, windowCtr: WindowCtr) -> Bool {
        let frame = windowCtr.frame()
        let mouseLocation = NSEvent.mouseLocation

        switch mode {
            case .expanded:
                let expandedFrame = NSRect(
                    x: frame.origin.x - kExpandedLength,
                    y: frame.origin.y - kExpandedLength,
                    width: frame.size.width + kExpandedLength * 2,
                    height: frame.size.height + kExpandedLength * 2
                )

                if !expandedFrame.contains(mouseLocation) {
                    windowCtr.close()
                    self.windowCtr = nil
                    return true
                }

            case .original:
                if !frame.contains(mouseLocation) {
                    windowCtr.close()
                    self.windowCtr = nil
                    return true
                }

            case .force:
                windowCtr.close()
                self.windowCtr = nil
                return true
        }

        return false
    }
}
