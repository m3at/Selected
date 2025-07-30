//
//  GetText.swift
//  Selected
//
//  Created by sake on 2024/2/29.
//

import Cocoa
import SwiftUI
import OpenAI
import Defaults

struct SelectedTextContext {
    var Text: String = ""
    var BundleID: String = ""
    var WebPageURL: String = "" // the url of webpage which contains text.
    var URLs = [String]() // all urls in text
    var Address: String = "" // last address in text
    var Editable: Bool = false // Is the current window editable? How to determine for browsers?
    // TODO: For IDEs or Editors, get the current editing filename, line number, etc.
}


let SelfBundleID = Bundle.main.bundleIdentifier ?? "io.kitool.Selected"

func getSelectedTextByAX(bundleID: String) -> String {
    let systemWideElement: AXUIElement = AXUIElementCreateSystemWide()
    var focusedWindow: AnyObject?
    var error: AXError = AXUIElementCopyAttributeValue(systemWideElement,
                                                       kAXFocusedApplicationAttribute as CFString,
                                                       &focusedWindow)
    if error != .success {
        print("Unable to get focused window: \(error)")
        return ""
    }
    
    if let focusedApp = focusedWindow as! AXUIElement? {
        var focusedElement: AnyObject?
        error = AXUIElementCopyAttributeValue(focusedApp,
                                              kAXFocusedUIElementAttribute as CFString,
                                              &focusedElement)
        
        if error == .success, let focusedElement = focusedElement as! AXUIElement? {
            
            var selectedTextValue: AnyObject?
            error = AXUIElementCopyAttributeValue(focusedElement,
                                                  kAXSelectedTextAttribute as CFString,
                                                  &selectedTextValue)
            if error == .success, let selectedText = selectedTextValue as? String {
                return selectedText
            } else {
                print("Unable to get selected text: \(error)")
            }
        }
    }
    return ""
}

func getUIElementProperties(_ element: AXUIElement) -> String? {
    var titleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
    
    var roleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
    
    if let title = titleValue as? String {
        print("UI element title: \(title)")
    }
    if let role = roleValue as? String {
        print("UI element role: \(role)")
        return role
    }
    return nil
}

func getSelectedText() -> SelectedTextContext? {
    var ctx = SelectedTextContext()
    let bundleID = getBundleID()
    ctx.BundleID = bundleID
    print("bundleID \(bundleID)")
    if bundleID == SelfBundleID {
        return nil
    }
    
    ctx.Editable = isCurrentFocusedElementEditable() ?? false
    if copyableAppList.contains(bundleID) {
        ctx.Editable = true
    }
    
    var selectedText = ""
    if isBrowser(id: bundleID) {
        // Accessibility features also get web content, but it might not be complete. Temporarily abandoning getting address bar content.
        // Address bar content cannot be obtained via script, but can be obtained via accessibility features.
        //        selectedText = getSelectedTextByAX(bundleID: bundleID)
        //        print("browser \(selectedText)")
        //        if selectedText.isEmpty {
        if let browserCtx = getSelectedTextByAppleScript(bundleID: bundleID) {
            selectedText = browserCtx.text
            ctx.WebPageURL = browserCtx.url
        }
        //        }
    } else {
        selectedText = getSelectedTextByAX(bundleID: bundleID)
    }
    
    if selectedText.isEmpty && SupportedCmdCAppList.contains(bundleID) {
        print("getSelectedTextBySimulateCommandC")
        selectedText = getSelectedTextBySimulateCommandC()
        if bundleID == "com.apple.iBooksX" {
            // hack for iBooks
            if let index = selectedText.endIndex(of: "\n\n摘录来自\n") {
                selectedText = String(selectedText[..<index])
            } else if let index = selectedText.endIndex(of: "\n\nExcerpt From\n") {
                selectedText = String(selectedText[..<index])
            }
        }
    }
    
    // get urls from selected text.
    let detector = try! NSDataDetector(types:
                                        NSTextCheckingResult.CheckingType.link.rawValue |
                                       NSTextCheckingResult.CheckingType.address.rawValue
    )
    let matches = detector.matches(in: selectedText, options: [], range: NSRange(location: 0, length: selectedText.count))
    var urlSet = Set<String>()
    var address = ""
    for match in matches {
        guard let range = Range(match.range, in: selectedText) else { continue }
        
        let item = String(selectedText[range])
        if match.resultType == .link {
            urlSet.insert(item)
        } else if match.resultType == .address {
            address = item
        }
    }
    ctx.URLs = Array(urlSet)
    ctx.Address = address
    ctx.Text = selectedText
    return ctx
}

extension StringProtocol {
    func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.lowerBound
    }
    func endIndex<S: StringProtocol>(of string: S) -> Index? {
        let indeics = ranges(of: string).map(\.lowerBound)
        if indeics.count > 0 {
            return indeics[indeics.count-1]
        }
        return nil
    }
}

let SupportedCmdCAppList: [String] = ["com.microsoft.VSCode",
                                      "com.microsoft.onenote.mac",
                                      "com.microsoft.Word",
                                      "com.microsoft.Powerpoint",
                                      "dev.zed.Zed",
                                      "dev.warp.Warp-Stable",
                                      "com.apple.iBooksX",
                                      "ru.keepcoder.Telegram",
                                      "com.laiwang.DingTalk",
                                      "dd.work.exclusive4aliding",
                                      "com.tencent.xinWeChat"]

let copyableAppList: [String] = ["dev.warp.Warp-Stable",
                                 "com.microsoft.onenote.mac",
                                 "com.microsoft.Word",
                                 "com.microsoft.Powerpoint",
                                 "dev.zed.Zed"]

func getSelectedTextBySimulateCommandC() -> String {
    let pboard =  NSPasteboard.general
    let lastCopyText = pboard.string(forType: .string)
    let lastChangeCount = pboard.changeCount
    
    let id = UUID().uuidString
    ClipService.shared.pauseMonitor(id)
    defer {ClipService.shared.resumeMonitor(id)}
    
    print("changeCount PressCopyKey \(id)")
    
    PressCopyKey()
    
    usleep(100000) // sleep 0.1s to wait NSPasteboard get copy string.
    if pboard.changeCount == lastChangeCount {
        // not copied
        return ""
    }
    
    let selectText = pboard.string(forType: .string)
    print("changeCount a \(pboard.changeCount)")
    pboard.clearContents()
    print("last content: \(String(describing: lastCopyText))")
    pboard.setString(lastCopyText ?? "", forType: .string)
    print("changeCount b \(pboard.changeCount)")
    
    return selectText ?? ""
}

func isCurrentFocusedElementEditable() -> Bool? {
    let systemWideElement = AXUIElementCreateSystemWide()
    
    var focusedApp: AnyObject?
    var result = AXUIElementCopyAttributeValue(systemWideElement,
                                               kAXFocusedApplicationAttribute as CFString,
                                               &focusedApp)
    guard result == .success, let axfocusedApp = focusedApp as! AXUIElement? else {
        return nil
    }
    
    // Get the currently focused UI element
    var focusedElement: AnyObject?
    result = AXUIElementCopyAttributeValue(axfocusedApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
    guard result == .success, let axFocusedElement = focusedElement as! AXUIElement? else {
        return nil
    }
    
    if let role = getUIElementProperties(axFocusedElement) {
        if role == "AXTextArea" {
            return true
        }
    }
    
    // Attempt to determine if the element is a text field by checking for a value attribute
    var value: AnyObject?
    let valueResult = AXUIElementCopyAttributeValue(axFocusedElement, kAXValueAttribute as CFString, &value)
    
    // Check if the value attribute exists and potentially editable
    if valueResult == .success, value != nil {
        var isAttributeSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axFocusedElement, kAXValueAttribute as CFString, &isAttributeSettable)
        print("editable \(isAttributeSettable.boolValue)")
        return isAttributeSettable.boolValue
    }
    return nil
}


// getBundleID, a frontmost window from other apps may not a fronmost app.
func getBundleID() -> String {
    let systemWideElement = AXUIElementCreateSystemWide()
    
    var focusedApp: AnyObject?
    let result = AXUIElementCopyAttributeValue(systemWideElement,
                                               kAXFocusedApplicationAttribute as CFString,
                                               &focusedApp)
    guard result == .success, let axfocusedApp = focusedApp as! AXUIElement? else {
        // chrome or vscode will return AXError(-25212)
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
    
    let focusedPid = pidForElement(element: axfocusedApp)
    let runningApp = NSRunningApplication(processIdentifier: focusedPid!)
    return runningApp?.bundleIdentifier ?? ""
}

func pidForElement(element: AXUIElement) -> pid_t? {
    var pid: pid_t = 0
    let error = AXUIElementGetPid(element, &pid)
    return (error == .success) ? pid : nil
}



func isBrowser(id: String) -> Bool {
    return isChrome(id: id) || isSafari(id: id)
}


func isChrome(id: String)-> Bool {
    let chromeList = [
        "com.google.Chrome",     // Google Chrome
        "com.microsoft.edgemac", // Microsoft Edge
        "company.thebrowser.Browser" // Arc
    ];
    return chromeList.contains(id)
}

func isArc(id: String)-> Bool {
    return "company.thebrowser.Browser"  == id
}

func isSafari(id: String)-> Bool {
    return id == "com.apple.Safari"
}

struct BroswerSelectedTextContext {
    var url: String
    var text: String
}

func getSelectedTextByAppleScript(bundleID: String) -> BroswerSelectedTextContext?{
    if isChrome(id: bundleID) {
        let selected = getSelectedTextByAppleScriptFromChrome(bundleID: bundleID)
        let url = getChromeCurrentTabURL(bundleID: bundleID)
        if isArc(id: bundleID) {
            // Arc browser gets text with double quotes at the beginning and end, which need to be removed.
            return BroswerSelectedTextContext(url: url, text: String(String(selected.dropLast(1)).dropFirst(1)))
        }
        return BroswerSelectedTextContext(url: url, text: selected)
    } else if isSafari(id: bundleID) {
        let selected = getSelectedTextByAppleScriptFromSafari(bundleID: bundleID)
        let url = getSafariCurrentTabURL(bundleID: bundleID)
        return BroswerSelectedTextContext(url: url, text: selected)
    }
    
    print("unknown \(bundleID)")
    return nil
}

// Requires enabling "Allow JavaScript from Apple Events" in Safari's Developer settings
func getSelectedTextByAppleScriptFromSafari(bundleID: String) -> String{
    // Add NSAppleEventsUsageDescription to Info.plist to describe the purpose of interacting with other apps via Apple Script, allowing users to grant permission.
    // No need to create a separate Info.plist, it won't work.
    print("bundleID: \(bundleID)")
    if let scriptObject =  NSAppleScript(source: """
                  with timeout of 5 seconds
                      tell application id "\(bundleID)"
                        tell front document
                            set selection_text to do JavaScript "window.getSelection().toString();"
                        end tell
                      end tell
                  end timeout
                  """) {
        
        var error: NSDictionary?
        let output = scriptObject.executeAndReturnError(&error)
        if (error != nil) {
            print("error: \(String(describing: error))")
            return ""
        } else {
            return output.stringValue!
        }
    }
    return ""
}


func getSelectedTextByAppleScriptFromChrome(bundleID: String) -> String{
    // Add NSAppleEventsUsageDescription to Info.plist to describe the purpose of interacting with other apps via Apple Script, allowing users to grant permission.
    // No need to create a separate Info.plist, it won't work.
    if let scriptObject =  NSAppleScript(source: """
                  with timeout of 5 seconds
                      tell application id "\(bundleID)"
                         tell active tab of front window
                             set selection_text to execute javascript "window.getSelection().toString();"
                         end tell
                      end tell
                  end timeout
                  """) {
        var error: NSDictionary?
        // TODO timeout?
        let output = scriptObject.executeAndReturnError(&error)
        if (error != nil) {
            print("error: \(String(describing: error))")
            return ""
        } else {
            return output.stringValue ?? ""
        }
    }
    return ""
}


func getSafariCurrentTabURL(bundleID: String) -> String {
    let script = """
tell application id "\(bundleID)"
set theUrl to URL of front document
end tell
"""
    
    if let scriptObject =  NSAppleScript(source: script) {
        var error: NSDictionary?
        // TODO timeout?
        let output = scriptObject.executeAndReturnError(&error)
        if (error != nil) {
            print("error: \(String(describing: error))")
            return ""
        } else {
            return output.stringValue ?? ""
        }
    }
    return ""
}


func getChromeCurrentTabURL(bundleID: String) -> String {
    let script = """
tell application id "\(bundleID)"
set theUrl to URL of active tab of front window
end tell
"""
    
    if let scriptObject =  NSAppleScript(source: script) {
        var error: NSDictionary?
        // TODO timeout?
        let output = scriptObject.executeAndReturnError(&error)
        if (error != nil) {
            print("error: \(String(describing: error))")
            return ""
        } else {
            return output.stringValue ?? ""
        }
    }
    return ""
}
