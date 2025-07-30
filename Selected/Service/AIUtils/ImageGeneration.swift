//
//  ImageGeneration.swift
//  Selected
//
//  Created by sake on 20/3/25.
//


import Foundation
import OpenAI

public struct ImageGeneration {
    /// Call Dall-E 3 to generate an image based on the provided parameters and return the image URL
    public static func generateDalle3Image(openAI: OpenAI, arguments: String) async throws -> String {
        let promptData = try JSONDecoder().decode(Dalle3Prompt.self, from: arguments.data(using: .utf8)!)
        let imageQuery = ImagesQuery(prompt: promptData.prompt, model: .dall_e_3)
        let res = try await openAI.images(query: imageQuery)
        guard let url = res.data.first?.url else {
            throw NSError(domain: "ImageGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image URL returned"])
        }
        print("image URL: %@", url)
        return url
    }
}

public struct Dalle3Prompt: Codable, Equatable {
    /// Prompt for image generation
    public let prompt: String
}
