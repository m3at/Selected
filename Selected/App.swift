//
//  App.swift
//  Selected
//
//  Created by sake on 2024/2/28.
//

import SwiftUI
import Accessibility
import AppKit
import Foundation
import Defaults


class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        setDefaultAppForCustomFileType()
        // No main window needed, and don't show in dock
        NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
        requestAccessibilityPermissions()

        DispatchQueue.main.async {
            PersistenceController.shared.startDailyTimer()
        }

        PluginManager.shared.loadPlugins()
        ConfigurationManager.shared.loadConfiguration()
        DispatchQueue.main.async {
            monitorMouseMove()
        }
        DispatchQueue.main.async {
            ClipService.shared.startMonitoring()
        }

        DispatchQueue.main.async {
            ClipboardHotKeyManager.shared.registerHotKey()
            SpotlightHotKeyManager.shared.registerHotKey()
        }

        // Register for space change notifications
        // NotificationCenter.default. is not applicable here.
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(spaceDidChange),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)
    }

    @objc func spaceDidChange() {
        // Triggered when the space changes
        ClipWindowManager.shared.forceCloseWindow()
        ChatWindowManager.shared.closeAllWindows(.force)
        SpotlightWindowManager.shared.forceCloseWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Handle opened files
            print("\(url.path)")
            PluginManager.shared.install(url: url)
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        // Disable global hotkeys when the app becomes active
        ClipboardHotKeyManager.shared.unregisterHotKey()
        SpotlightHotKeyManager.shared.unregisterHotKey()
    }

    func applicationDidResignActive(_ notification: Notification) {
        if Defaults[.enableClipboard] {
            // Enable global hotkeys when the app goes to the background
            ClipboardHotKeyManager.shared.registerHotKey()
        }
        SpotlightHotKeyManager.shared.registerHotKey()
    }
}


func setDefaultAppForCustomFileType() {
    let customUTI = "io.kitool.selected.ext"
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.kitool.Selected"
    print("bundleIdentifier \(bundleIdentifier)")

    LSSetDefaultRoleHandlerForContentType(customUTI as CFString, .editor, bundleIdentifier as CFString)
}


@main
struct SelectedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra() {
            MenuItemView()
        } label: {
            Label {
                Text("Selected")
            } icon: {
                Image(systemName: "pencil.scribble")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            }
            .help("Selected")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            SelectedMainMenu()
        }.handlesExternalEvents(matching: [])
        Settings {
            SettingsView()
        }
    }
}


func requestAccessibilityPermissions() {
    // Check permissions
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let accessEnabled = AXIsProcessTrustedWithOptions(options)

    print("accessEnabled: \(accessEnabled)")

    if !accessEnabled {
        // Request permissions
        // Note: This cannot be a sandbox app, otherwise it won't be visible in Accessibility settings.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let kExpandedLength: CGFloat = 100


// Monitor mouse movement
func monitorMouseMove() {
    var eventState = EventState()
    var hoverWorkItem: DispatchWorkItem?
    var lastSelectedText = ""

    NSEvent.addGlobalMonitorForEvents(matching:
                                        [.mouseMoved, .leftMouseUp, .leftMouseDragged, .keyDown, .scrollWheel]
    ) { (event) in
        if PauseModel.shared.pause {
            return
        }
        if event.type == .mouseMoved {
            if WindowManager.shared.closeOnlyPopbarWindows(.expanded) {
                lastSelectedText = ""
            }
            eventState.lastMouseEventType = .mouseMoved
        } else if event.type == .scrollWheel {
            lastSelectedText = ""
            _ = WindowManager.shared.closeAllWindows(.original)
        } else {
            print("event \(eventTypeMap[event.type]!)  \(eventTypeMap[eventState.lastMouseEventType]!)")
            var updatedSelectedText = false
            if eventState.isSelected(event: event) {
                if let ctx = getSelectedText() {
                    print("SelectedContext %@", ctx)
                    if !ctx.Text.isEmpty {
                        updatedSelectedText = true
                        if lastSelectedText != ctx.Text {
                            lastSelectedText = ctx.Text
                            hoverWorkItem?.cancel()

                            let workItem = DispatchWorkItem {
                                WindowManager.shared.createPopBarWindow(ctx)
                            }
                            hoverWorkItem = workItem
                            let delay = 0.2
                            // Execute after 0.2 seconds
                            // Fix: In VS Code and Zed, Cmd+C can copy the entire line when no text is selected.
                            // However, these apps only get selected text via Cmd+C.
                            // This leads to the pop-up bar appearing regardless of where you click if we only listen for leftMouseUp.
                            // Therefore, we change it to: if the last leftMouseUp time was less than 0.5s, it's a double-click.
                            // Double-click selects a word, triple-click selects a line.
                            // Also, we listen for Cmd+A (select all) and Cmd+Shift+Arrow (partial selection).
                            // If another left click occurs within 0.2 seconds, cancel the previous window drawing. This prevents window flickering.
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                        }
                    }
                }
            }

            if !updatedSelectedText &&
                getBundleID() != SelfBundleID {
                lastSelectedText = ""
                _ = WindowManager.shared.closeAllWindows(.original)
                ChatWindowManager.shared.closeAllWindows(.original)
            }
        }
    }
    print("monitorMouseMove")
}

struct EventState {
    // In VS Code and Zed, Cmd+C can copy the entire line when no text is selected.
    // However, these apps only get selected text via Cmd+C.
    // This leads to the pop-up bar appearing regardless of where you click if we only listen for leftMouseUp.
    // Therefore, we change it to: if the last leftMouseUp time was less than 0.5s, it's a double-click.
    // Double-click selects a word, triple-click selects a line.
    // Also, we listen for Cmd+A (select all) and Cmd+Shift+Arrow (partial selection).
    var lastLeftMouseUPTime = 0.0
    var lastMouseEventType: NSEvent.EventType = .leftMouseUp

    let keyCodeArrows: [UInt16] = [Keycode.leftArrow, Keycode.rightArrow, Keycode.downArrow, Keycode.upArrow]

    mutating func isSelected(event: NSEvent ) -> Bool {
        defer {
            if event.type != .keyDown {
                lastMouseEventType = event.type
            }
        }
        if event.type == .leftMouseUp {
            let selected =  lastMouseEventType == .leftMouseDragged ||
            ((lastMouseEventType == .leftMouseUp) && (event.timestamp - lastLeftMouseUPTime < 0.5))
            lastLeftMouseUPTime = event.timestamp
            return selected
        } else if event.type == .keyDown {
            if event.keyCode == Keycode.a {
                return event.modifierFlags.contains(.command) &&
                !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.control)
            } else if keyCodeArrows.contains( event.keyCode) {
                let keyMask: NSEvent.ModifierFlags =  [.command, .shift]
                return event.modifierFlags.intersection(keyMask) == keyMask
            }
        }
        return false
    }
}

let eventTypeMap: [ NSEvent.EventType: String] = [
    .mouseMoved: "mouseMoved",
    .keyDown: "keydonw",
    .keyUp: "keyup",
    .leftMouseUp: "leftMouseUp",
    .leftMouseDragged: "leftMouseDragged",
    .scrollWheel: "scrollWheel"
]
