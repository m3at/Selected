//
//  ContentView.swift
//  Selected
//
//  Created by sake on 2025/3/16.
//

import SwiftUI
import MarkdownUI
import LaTeXSwiftUI
import Highlightr

struct LaTeXImageProvider: InlineImageProvider, ImageProvider {
    let latexFormulas: [String: String]

    func image(with url: URL, label: String) async throws -> Image {
        if url.scheme == "latex", let id = url.host, let formula = latexFormulas[id] {
            return try await renderLatexImage(formula)
        }
        return try await DefaultInlineImageProvider.default.image(with: url, label: label)
    }

    public func makeImage(url: URL?) -> some View {
        if let url = url, url.scheme == "latex", let id = url.host, let formula = latexFormulas[id] {
            LaTeX(formula)
                .frame(maxWidth: 500)
                .padding(.vertical, 0)
        } else if let url = url {
            DefaultImageProvider.default.makeImage(url: url)
        } else {
            DefaultImageProvider.default.makeImage(url: nil)
        }
    }

    @MainActor
    private func renderLatexImage(_ formula: String) async throws -> Image {
        // Create view on MainActor
        let latexView = LaTeX(formula)
            .frame(maxWidth: 500)
            .padding(.vertical, 0)

        // Set renderer
        let renderer = ImageRenderer(content: latexView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Render to image
        if let nsImage = renderer.nsImage {
            return Image(nsImage: nsImage)
        }

        throw URLError(.cannotDecodeContentData)
    }
}

struct MarkdownWithLateXView: View {

    @Environment(\.colorScheme) private var colorScheme
    var highlighter = CustomCodeSyntaxHighlighter()

    @Binding var markdownString: String

    // Placeholder for processed block formulas
    private let latexBlockPlaceholder = "LATEX_BLOCK_"

    // Regex for inline LaTeX formulas
    private let inlineLatexPattern = #"\$(.*?)\$"#
    private let inlineLatexPattern2 = #"\\\((.*?)\\\)"#

    // Regex for block LaTeX formulas
    private let blockLatexPattern = #"\$\$(.*?)\$\$"#
    private let blockLatexPattern2 = #"\\\[(.*?)\\\]"#

    var body: some View {
        let (processedMarkdown, latexFormulas) = processMarkdownWithLatex()

        return Markdown{processedMarkdown}.markdownBlockStyle(\.codeBlock) { configuration in
            // Process block formula placeholders
            if let id = extractLatexId(from: configuration.language ?? "", prefix: latexBlockPlaceholder),
               let formula = latexFormulas[id] {
                LaTeX(formula)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                codeBlock(configuration)
            }
        }.markdownInlineImageProvider(LaTeXImageProvider(latexFormulas: latexFormulas))
            .markdownImageProvider(LaTeXImageProvider(latexFormulas: latexFormulas))
    }

    func getLanguage(_ configuration: CodeBlockConfiguration) -> String {
        guard let language = configuration.language else {
            return "plaintext"
        }
        return language == "" ? "plaintext": language
    }

    @ViewBuilder
    private func codeBlock(_ configuration: CodeBlockConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(getLanguage(configuration))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()

                Image(systemName: "clipboard")
                    .onTapGesture {
                        copyToClipboard(configuration.content)
                    }
            }
            .padding(.horizontal, 5)

            Divider()

            // wrap long lines
            highlighter.setTheme(theme: codeTheme).highlightCode(configuration.content, language: configuration.language)
                .relativeLineSpacing(.em(0.5))
                .padding(5)
                .markdownMargin(top: .em(1), bottom: .em(1))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }


    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private var codeTheme: CodeTheme {
        switch self.colorScheme {
            case .dark:
                return .dark
            default:
                return .light
        }
    }


    // Extract LaTeX formula ID
    private func extractLatexId(from text: String, prefix: String) -> String? {
        guard text.hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count))
    }

    private func blockLatex(markdown: String, latexFormulas: inout [String: String], blockLatexPattern: String)  -> (String){
        // Process block formulas
        let result = markdown
        var forumlaIDs = [String: String]()

        let blockLatexRegex = try! NSRegularExpression(pattern: blockLatexPattern, options: [.dotMatchesLineSeparators])
        let blockMatches = blockLatexRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        let mutableResult = NSMutableString(string: result)
        for match in blockMatches.reversed() {
            if let range = Range(match.range, in: result) {
                let formula = String(result[range])
                let latexContent = formula
                var id = ""
                if let val = forumlaIDs[latexContent] {
                    id = val
                } else {
                    id = UUID().uuidString
                    latexFormulas[id] = latexContent
                    forumlaIDs[latexContent] = id
                }

                // Replace with custom code block
                let replacement = "\n```\(latexBlockPlaceholder)\(id)\n```\n"
                mutableResult.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return String(mutableResult)
    }

    private func inlineLatex(markdown: String, latexFormulas: inout [String: String], inlineLatexPattern: String)  -> (String) {
        // Process inline formulas
        let result = markdown
        var forumlaIDs = [String: String]()

        let inlineLatexRegex = try! NSRegularExpression(pattern: inlineLatexPattern, options: [])
        let inlineMatches = inlineLatexRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        let mutableInlineResult = NSMutableString(string: result)

        for match in inlineMatches.reversed() {
            if let range = Range(match.range, in: result) {
                let formula = String(result[range])
                let latexContent = formula
                var id = ""
                if let val = forumlaIDs[latexContent] {
                    id = val
                } else {
                    id = UUID().uuidString
                    latexFormulas[id] = latexContent
                    forumlaIDs[latexContent] = id
                }

                // Use inline image with custom URL schema
                let replacement = "![LaTeX formula](latex://\(id))"
                mutableInlineResult.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return String(mutableInlineResult)
    }

    // Process LaTeX formulas in Markdown, returning processed text and formula dictionary
    private func processMarkdownWithLatex() -> (String, [String: String]) {
        var result = markdownString
        var latexFormulas = [String: String]()

        result = blockLatex(markdown: result, latexFormulas: &latexFormulas, blockLatexPattern: blockLatexPattern)

        result = blockLatex(markdown: result, latexFormulas: &latexFormulas, blockLatexPattern: blockLatexPattern2)

        result = inlineLatex(markdown: result, latexFormulas: &latexFormulas, inlineLatexPattern: inlineLatexPattern)

        result = inlineLatex(markdown: result, latexFormulas: &latexFormulas, inlineLatexPattern: inlineLatexPattern2)
        return (result, latexFormulas)
    }
}
