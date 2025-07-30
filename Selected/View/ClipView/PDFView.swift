//
//  PDFView.swift
//  Selected
//
//  Created by sake on 2024/4/7.
//

import Foundation
import SwiftUI
import PDFKit

struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true // Automatically scale the PDF to fit the view
        pdfView.autoresizingMask = [.width, .height]
        // Load PDF document
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // This method can be left empty as the PDFView content does not change frequently
    }
}
