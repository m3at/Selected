//
//  PluginInfo.swift
//  Selected
//
//  Created by sake on 2024/3/11.
//

import Foundation
import SwiftUI
import Yams


struct SupportedApp: Decodable {
    var bundleID: String
}

struct Supported: Decodable {
    var apps: [SupportedApp]?
    var urls: [String]?
    
    func match(url: String, bundleID: String) -> Bool {
        if apps == nil && urls == nil {
            return true
        }
        var appsEmpty = true
        if let apps = apps {
            for app in apps {
                if app.bundleID == bundleID {
                    return true
                }
            }
            appsEmpty = apps.isEmpty
        }
        
        var urlsEmpty = true
        if let urls = urls {
            for supportedURL in urls {
                if url.contains(supportedURL) {
                    return true
                }
            }
            urlsEmpty = url.isEmpty
        }
        return urlsEmpty && appsEmpty
    }
}

struct PluginInfo: Decodable {
    var icon: String
    var name: String
    var version: String?
    var minSelectedVersion: String?
    var description: String?
    var options: [Option]
    
    // not in config
    var enabled: Bool = true
    var pluginDir = ""
    
    
    enum CodingKeys: String, CodingKey {
        case icon, name, version,
             minSelectedVersion, description,
             options
    }
    
    init() {
        self.icon = "symbol:pencil.and.scribble"
        self.name = "system"
        self.options = [Option]()
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.icon = try values.decode(String.self, forKey: .icon)
        self.name = try values.decode(String.self, forKey: .name)
        
        if values.contains(.version) {
            self.version = try values.decode(String.self, forKey: .version)
        }
        if values.contains(.minSelectedVersion) {
            self.minSelectedVersion = try values.decode(String.self, forKey: .minSelectedVersion)
        }
        if values.contains(.description) {
            self.description = try values.decode(String.self, forKey: .description)
        }
        self.options = [Option]()
        if values.contains(.options) {
            self.options = try values.decode([Option].self, forKey: .options)
        }
    }
    
    func getOptionsValue() -> [String:String] {
        var dict = [String:String]()
        
        for option in options {
            if option.type == .boolean {
                let val = getBoolOption(pluginName: name, identifier: option.identifier)
                dict[option.identifier] = val.description
            } else {
                if let val = getStringOption(pluginName: name, identifier: option.identifier) {
                    dict[option.identifier] = val
                } else {
                    dict[option.identifier] = option.defaultVal
                }
            }
        }
        return dict
    }
}

struct Plugin: Decodable {
    var info: PluginInfo
    var actions: [Action]
}


// PluginManager manages various plugins. Plugins are stored in "Library/Application Support/Selected/Extensions".
class PluginManager: ObservableObject {
    private var extensionsDir: URL
    private let filemgr = FileManager.default
    
    @Published var plugins = [Plugin]()
    
    // notify for option value changed
    // we may use option value to construct action title.
    // It's useful when we want to see action real title at the time we change option value.
    @Published var optionValueChangeCnt = 0
    
    static let shared = PluginManager()
    
    init(){
        let fileManager = FileManager.default
        // Application subdirectory
        extensionsDir = appSupportURL.appendingPathComponent("Extensions", isDirectory: true)
        
        // Check if the directory exists, otherwise try to create it
        if !fileManager.fileExists(atPath: extensionsDir.path) {
            try! fileManager.createDirectory(at: extensionsDir, withIntermediateDirectories: true, attributes: nil)
        }
        NSLog("Application Extensions Directory: \(extensionsDir.path)")
    }
    
    private func copyFile(fpath: String, tpath: String) -> Bool{
        NSLog("install from \(fpath) to \(tpath)")
        if filemgr.contentsEqual(atPath: fpath, andPath: tpath) {
            return false
        }
        do{
            NSLog("install to \(tpath)")
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: tpath){
                try fileManager.removeItem(atPath: tpath)
            }
            
            try fileManager.copyItem(atPath: fpath, toPath: tpath)
            return true
        } catch {
            print("install: an unexpected error: \(error)")
        }
        return false
    }
    
    func install(url: URL) {
        if url.hasDirectoryPath {
            NSLog("install \(url.lastPathComponent)")
            if copyFile(fpath: url.path(percentEncoded: false), tpath: extensionsDir.appending(component: url.lastPathComponent).path(percentEncoded: false)) {
                loadPlugins()
            }
        }
    }
    
    func remove(_ pluginDir: String, _ pluginName: String) {
        do {
            try filemgr.removeItem(at: extensionsDir.appendingPathComponent(pluginDir, isDirectory: true))
            removeOptionsOf(pluginName: pluginName)
        } catch{
            NSLog("remove plugin \(pluginDir): \(error)")
        }
        loadPlugins()
    }
    
    func getPlugins() -> [Plugin] {
        return self.plugins
    }
    
    func loadPlugins(){
        var list = [Plugin]()
        let pluginDirs = try! filemgr.contentsOfDirectory(atPath: extensionsDir.path)
        NSLog("plugins \(pluginDirs)")
        for pluginDir in pluginDirs {
            let cfgPath = extensionsDir.appendingPathComponent(pluginDir, isDirectory: true).appendingPathComponent("config.yaml", isDirectory: false)
            if filemgr.fileExists(atPath: cfgPath.path) {
                let readFile = try! String(contentsOfFile: cfgPath.path, encoding: String.Encoding.utf8)
                let decoder = YAMLDecoder()
                var plugin: Plugin = try! decoder.decode(Plugin.self, from: readFile.data(using: .utf8)!)
                NSLog("plugin \(plugin)")
                
                plugin.info.pluginDir = pluginDir
                if plugin.info.icon.hasPrefix("file://./"){
                    plugin.info.icon = "file://"+extensionsDir.appendingPathComponent(pluginDir, isDirectory: true).appendingPathComponent(plugin.info.icon.trimPrefix("file://./"), isDirectory: false).path
                }
                
                for i in plugin.actions.indices {
                    var action = plugin.actions[i]
                    do {
                        var meta = action.meta
                        if meta.icon.hasPrefix("file://./"){
                            meta.icon =  "file://"+extensionsDir.appendingPathComponent(pluginDir, isDirectory: true).appendingPathComponent(action.meta.icon.trimPrefix("file://./"), isDirectory: false).path
                        }
                        action.meta = meta
                        
                        if let runCommand = action.runCommand {
                            runCommand.pluginPath = extensionsDir.appendingPathComponent(pluginDir, isDirectory: true).path
                        }
                        
                        if let gpt = action.gpt, var tools = gpt.tools {
                            tools =  tools.map { tool in
                                var mutTool = tool
                                mutTool.workdir  = extensionsDir.appendingPathComponent(pluginDir, isDirectory: true).path
                                return mutTool
                            }
                            gpt.tools = tools
                        }
                        
                        if let regex = action.meta.regex {
                            _ = try Regex(regex)
                        }
                    } catch {
                        NSLog("validate action error \(error)")
                    }
                    plugin.actions[i] = action
                }
                
                list.append(plugin)
            }
        }
        self.plugins = list
    }
    
    var allActions: [PerformAction] {
        var list = [PerformAction]()
        list.append(WebSearchAction().generate(
            generic: GenericAction(title: "Search", icon: "symbol:magnifyingglass", after: "", identifier: "selected.websearch")
        ))
        
        let pluginList = plugins
        NSLog("get all")
        pluginList.forEach { Plugin in
            if !Plugin.info.enabled {
                return
            }
            Plugin.actions.forEach { Action in
                var generic = Action.meta
                generic.title = replaceOptions(content: generic.title, selectedText: "", options: Plugin.info.getOptionsValue())
                
                if let url = Action.url {
                    list.append(url.generate(pluginInfo: Plugin.info, generic: generic))
                    return
                }
                if let service = Action.service {
                    list.append(service.generate(generic: generic))
                    return
                }
                if let keycombo = Action.keycombo {
                    list.append(keycombo.generate(pluginInfo: Plugin.info, generic: generic))
                    return
                }
                if let gpt = Action.gpt {
                    list.append(gpt.generate(pluginInfo: Plugin.info, generic: generic))
                    return
                }
                if let script = Action.runCommand {
                    list.append(script.generate(pluginInfo: Plugin.info, generic: generic))
                    return
                }
            }
        }
        
        list.append(TranslationAction(target: "cn").generate(
            generic: GenericAction(title: "翻译到中文", icon: "square 译中", after: "", identifier: "selected.translation.cn")
        ))
        list.append(TranslationAction(target: "en").generate(
            generic: GenericAction(title: "Translate to English", icon: "symbol:e.square", after: "", identifier: "selected.translation.en")
        ))
        list.append(CopyAction().generate(
            generic: GenericAction(title: "Copy", icon: "symbol:doc.on.clipboard", after: "", identifier: "selected.copy")
        ))
        list.append(SpeackAction().generate(
            generic: GenericAction(title: "Speak", icon: "symbol:play.circle", after: "", identifier: "selected.speak")
        ))
        
        return list
    }
}
