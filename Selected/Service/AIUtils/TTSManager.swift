//
//  TTSManager.swift
//  Selected
//
//  Created by sake on 20/3/25.
//


import Foundation
import AVFoundation
import Defaults
import SwiftUI
import OpenAI

public class TTSManager {

    // MARK: - Properties

    /// System speech synthesizer, used when OpenAI APIKey is empty to call system TTS
    private static let speechSynthesizer = AVSpeechSynthesizer()

    /// Audio player for OpenAI voice synthesis playback
    private static var audioPlayer: AVAudioPlayer?

    /// TTS cache data structure
    private struct VoiceData {
        var data: Data
        var lastAccessTime: Date
    }

    /// Cache dictionary, key is the hash value of the text
    private static var voiceDataCache = [Int: VoiceData]()

    // MARK: - Cache Management

    /// Clear unused data in the cache that exceeds 120 seconds
    private static func clearExpiredVoiceData() {
        let now = Date()
        voiceDataCache = voiceDataCache.filter { $0.value.lastAccessTime.addingTimeInterval(120) >= now }
    }

    // MARK: - System TTS

    /// Use system speech synthesis (AVSpeechSynthesizer) to read text
    private static func systemSpeak(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.pitchMultiplier = 0.8
        utterance.postUtteranceDelay = 0.2
        utterance.volume = 0.8
        speechSynthesizer.speak(utterance)
    }

    // MARK: - OpenAI TTS Call

    /// Call voice synthesis via OpenAI API and play the generated voice directly
    private static func play(text: String) async {
        clearExpiredVoiceData()
        let hashValue = text.hash
        if let cached = voiceDataCache[hashValue] {
            print("Using cached TTS data")
            audioPlayer?.stop()
            do {
                audioPlayer = try AVAudioPlayer(data: cached.data)
                audioPlayer?.play()
            } catch {
                print("Audio player error: \(error)")
            }
            return
        }

        let configuration = OpenAI.Configuration(token: Defaults[.openAIAPIKey],
                                                 host: Defaults[.openAIAPIHost],
                                                 timeoutInterval: 60.0, parsingOptions: .relaxed)
        let openAI = OpenAI(configuration: configuration)
        let model = Defaults[.openAITTSModel]
        let instructions = model == .gpt_4o_mini_tts ? Defaults[.openAITTSInstructions] : ""
        let query = AudioSpeechQuery(model: model,
                                     input: text,
                                     voice: Defaults[.openAIVoice],
                                     instructions: instructions,
                                     responseFormat: .mp3,
                                     speed: 1.0)

        do {
            let result = try await openAI.audioCreateSpeech(query: query)
            voiceDataCache[hashValue] = VoiceData(data: result.audio, lastAccessTime: Date())
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: result.audio)
            audioPlayer?.play()
        } catch {
            print("audioCreateSpeech error: \(error)")
        }
    }

    /// Fetch TTS audio data via OpenAI API, suitable for scenarios requiring custom playback (e.g., playing in a new window)
    private static func fetchTTSData(text: String) async -> Data? {
        clearExpiredVoiceData()
        let hashValue = text.hash
        if let cached = voiceDataCache[hashValue] {
            print("Using cached TTS data")
            return cached.data
        }

        let configuration = OpenAI.Configuration(token: Defaults[.openAIAPIKey],
                                                 host: Defaults[.openAIAPIHost],
                                                 timeoutInterval: 60.0, parsingOptions: .relaxed)
        let openAI = OpenAI(configuration: configuration)
        let model = Defaults[.openAITTSModel]
        let instructions = model == .gpt_4o_mini_tts ? Defaults[.openAITTSInstructions] : ""
        let query = AudioSpeechQuery(model: model,
                                     input: text,
                                     voice: Defaults[.openAIVoice],
                                     instructions: instructions,
                                     responseFormat: .mp3,
                                     speed: 1.0)
        do {
            let result = try await openAI.audioCreateSpeech(query: query)
            voiceDataCache[hashValue] = VoiceData(data: result.audio, lastAccessTime: Date())
            return result.audio
        } catch {
            print("audioCreateSpeech error: \(error)")
            return nil
        }
    }

    // MARK: - Comprehensive Call Entry Point

    /// Comprehensive TTS playback function, determines whether to call system TTS or OpenAI TTS based on OpenAI APIKey and text content
    ///
    /// - Parameters:
    ///   - text: Text to be read aloud
    ///   - view: Whether to play in a view window (suitable for multiple sentences); defaults to true
    ///
    /// If OpenAI APIKey is empty, system TTS is called. Otherwise:
    /// - If the text is a word or view is false, play the voice directly.
    /// - Otherwise, get TTS data and play it in a new window (requires WindowManager to implement relevant methods).
    public static func speak(_ text: String, view: Bool = true) async {
        // If OpenAI APIKey is not configured, call system voice
        if Defaults[.openAIAPIKey].isEmpty {
            systemSpeak(text)
        } else {
            // isWord(str:) is a custom helper method to determine if the text is a word (needs to be implemented by you)
            if isWord(str: text) || !view {
                await play(text: text)
            } else {
                if let data = await fetchTTSData(text: text) {
                    DispatchQueue.main.async {
                        // WindowManager.shared.createAudioPlayerWindow(_:) is a custom method
                        // used to play audio data in a new window; implement it yourself.
                        WindowManager.shared.createAudioPlayerWindow(data)
                    }
                }
            }
        }
    }

    /// Stop all ongoing speech synthesis playback, including system TTS and OpenAI TTS
    public static func stopSpeak() {
        speechSynthesizer.stopSpeaking(at: .word)
        audioPlayer?.stop()
    }
}
