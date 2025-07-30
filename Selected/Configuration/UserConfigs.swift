//
//  UserConfigs.swift
//  Selected
//
//  Created by sake on 2024/3/17.
//

import Foundation

typealias ActionID = String

// AppCondition specifies the list of actions for a specific app.
struct AppCondition: Codable {
    let bundleID: String    // bundleID of app
    var actions: [ActionID] // List of enabled plugins and their display order for this app
}

// URLCondition specifies the list of actions for a specific URL.
struct URLCondition: Codable {
    let url: String         // URL condition
    var actions: [ActionID] // List of enabled plugins and their display order for this URL
}

struct UserConfiguration: Codable {
    var defaultActions: [ActionID]
    var appConditions: [AppCondition] // User-defined app conditions
    var urlConditions: [URLCondition] // User-defined URL conditions
}

// ConfigurationManager reads and saves complex application configurations, such as which actions are enabled for which apps.
// Configurations are saved in "Library/Application Support/Selected".
class ConfigurationManager {
    static let shared = ConfigurationManager()
    private let configurationFileName = "UserConfiguration.json"
    
    var userConfiguration: UserConfiguration
    
    init() {
        userConfiguration = UserConfiguration(defaultActions: [], appConditions: [], urlConditions: [])
        loadConfiguration()
    }
    
    func getAppCondition(bundleID: String) -> AppCondition? {
        for condition in userConfiguration.appConditions {
            if condition.bundleID == bundleID {
                return condition
            }
        }
        // If no specific app condition is found, return default actions if they exist.
        if userConfiguration.defaultActions.count > 0 {
            return AppCondition(bundleID: bundleID, actions: userConfiguration.defaultActions)
        }
        return nil
    }
    
    func getURLCondition(url: String) -> URLCondition? {
        for condition in userConfiguration.urlConditions {
            if url.contains(condition.url) {
                return condition
            }
        }
        return nil
    }
    
    func loadConfiguration() {
        let fileURL = appSupportURL.appendingPathComponent(configurationFileName)
        print("UserConfiguration \(fileURL.absoluteString)")
        do {
            let data = try Data(contentsOf: fileURL)
            userConfiguration = try JSONDecoder().decode(UserConfiguration.self, from: data)
        } catch {
            print("Error loading configuration: \(error)")
        }
    }
    
    func saveConfiguration() {
        let fileURL = appSupportURL.appendingPathComponent(configurationFileName)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(userConfiguration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Error saving configuration: \(error)")
        }
    }
}
