//
//  FunctionDefinition.swift
//  Selected
//
//  Created by sake on 20/3/25.
//


import Foundation
import OpenAI

public struct FunctionDefinition: Codable, Equatable {
    /// Function name, must only contain a-z, A-Z, 0-9, underscore or hyphen, max length 64.
    public let name: String
    /// Description of the function
    public let description: String
    /// JSON Schema description of function parameters
    public let parameters: String
    /// Array of commands required to execute this function
    public var command: [String]?
    /// Working directory for command execution
    public var workdir: String?
    /// Whether to display execution results, defaults to true
    public var showResult: Bool? = true
    /// Optional template string
    public var template: String?

    /// Run the command corresponding to this function
    func Run(arguments: String, options: [String: String] = [:]) throws -> String? {
        guard let command = self.command else {
            return nil
        }
        // Get parameters excluding the first element
        var args = Array(command.dropFirst())
        args.append(arguments)

        // Set environment variables
        var env = [String: String]()
        options.forEach { key, value in
            env["SELECTED_OPTIONS_\(key.uppercased())"] = value
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:" + path
        }
        // Note: This assumes executeCommand(workdir:command:arguments:withEnv:) is implemented elsewhere
        return try executeCommand(workdir: workdir!, command: command[0], arguments: args, withEnv: env)
    }

    /// Parse JSON Schema parameters into FunctionParameters object
    func getParameters() -> AnyJSONSchema? {
        return try? JSONDecoder().decode(AnyJSONSchema.self, from: parameters.data(using: .utf8)!)
    }
}
