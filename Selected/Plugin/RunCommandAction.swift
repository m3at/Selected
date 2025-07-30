//
//  ScriptAction.swift
//  Selected
//
//  Created by sake on 2024/3/19.
//

import Foundation
import AppKit


class RunCommandAction: Decodable {
    var command: [String]
    var pluginPath: String? // we will execute command in pluginPath.

    enum CodingKeys: String, CodingKey {
        case command
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        command = try values.decode([String].self, forKey: .command)
    }


    init(command: [String], options: [Option]) {
        self.command = command
    }

    func generate(pluginInfo: PluginInfo, generic: GenericAction) -> PerformAction {
        return PerformAction(actionMeta:
                                generic, complete: { ctx in
            guard self.command.count > 0 else {
                return
            }

            guard let pluginPath = self.pluginPath else {
                return
            }


            let joinedURLs = ctx.URLs.joined(separator: "\n")

            var env = ["SELECTED_TEXT": ctx.Text,
                       "SELECTED_BUNDLEID": ctx.BundleID,
                       "SELECTED_ACTION": generic.identifier,
                       "SELECTED_WEBPAGE_URL": ctx.WebPageURL,
                       "SELECTED_URLS": joinedURLs]
            let optionVals = pluginInfo.getOptionsValue()
            optionVals.forEach{ (key: String, value: String) in
                env["SELECTED_OPTIONS_"+key.uppercased()] = value
            }
            if let path = ProcessInfo.processInfo.environment["PATH"] {
                env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:" + path
            }

            do {
                if let output = try executeCommand(
                    workdir: pluginPath,
                    command: self.command[0],
                    arguments: [String](self.command[1...]),
                    withEnv: env) {
                    if ctx.Editable && generic.after == kAfterPaste {
                        pasteText(output)
                    } else if generic.after == kAfterCopy {
                        copyText(output)
                    } else if generic.after == kAfterShow {
                        WindowManager.shared.createTextWindow(output)
                    }
                }
            } catch {
                NSLog("executeCommand: \(error)")
            }
        })
    }
}

func pasteText(_ text: String) {
    let id = UUID().uuidString
    ClipService.shared.pauseMonitor(id)
    defer {
        ClipService.shared.resumeMonitor(id)
    }
    let pasteboard = NSPasteboard.general
    let lastCopyText = pasteboard.string(forType: .string)

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    PressPasteKey()
    usleep(100000)
    pasteboard.setString(lastCopyText ?? "", forType: .string)
}

func copyText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

public func executeCommand(
    workdir: String, command: String, arguments: [String] = [], withEnv env: [String:String]) throws -> String? {
        let process = Process()
        process.qualityOfService = .default
        let stdOutPipe = Pipe()
        let stdErrPipe = Pipe()
        var path: String?
        if let p = ProcessInfo.processInfo.environment["PATH"] {
            path = "/opt/homebrew/bin:/opt/homebrew/sbin:" + p
        }

        let executableURL = findExecutablePath(commandName: command,
                                               currentDirectoryURL:  URL(fileURLWithPath: workdir),
                                               path: path)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdOutPipe
        process.standardError = stdErrPipe
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)

        var copiedEnv = env
        copiedEnv["PATH"] = path
        process.environment = copiedEnv

        var stdOutData = Data()
        var stdErrData = Data()

        // Create a Dispatch group to handle reading from pipes asynchronously
        let group = DispatchGroup()

        // Asynchronously read stdout
        group.enter()
        stdOutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdOutPipe.fileHandleForReading.readabilityHandler = nil
                group.leave()
            } else {
                stdOutData.append(data)
            }
        }

        // Asynchronously read stderr
        group.enter()
        stdErrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdErrPipe.fileHandleForReading.readabilityHandler = nil
                group.leave()
            } else {
                stdErrData.append(data)
            }
        }


        let timeout: TimeInterval = 60 // 1 min
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
                print("Process terminated due to timeout.")
            }
            timer.cancel()
        }

        var output: String? = nil

        try process.run()
        timer.activate()
        process.waitUntilExit()

        // Ensure all data has been read
        group.wait()

        output = String(data: stdOutData + stdErrData, encoding: .utf8)
        return output
    }


private func findExecutablePath(commandName: String, currentDirectoryURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, path: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
    let fileManager = FileManager.default
    // First check if it's an absolute path
    let executableURL = URL(fileURLWithPath: commandName)
    if executableURL.isFileURL, fileManager.isExecutableFile(atPath: executableURL.path) {
        return executableURL
    }

    // Check if the command is in the current directory
    if let currentDirectoryURL = currentDirectoryURL {
        let currentDirectoryExecutable = currentDirectoryURL.appendingPathComponent(commandName)
        if FileManager.default.isExecutableFile(atPath: currentDirectoryExecutable.path) {
            return currentDirectoryExecutable
        }
    }

    // Then check if the command is in a directory in the PATH environment variable
    if let path = path {
        let paths = path.split(separator: ":").map { String($0) }
        for p in paths {
            let potentialURL = URL(fileURLWithPath: p).appendingPathComponent(commandName)
            if FileManager.default.isExecutableFile(atPath: potentialURL.path) {
                return potentialURL
            }
        }
    }

    // Return nil if the executable file is not found
    return nil
}
