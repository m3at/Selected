//
//  QuickLookView.swift
//  Selected
//
//  Created by sake on 2024/4/7.
//

import SwiftUI
import QuickLookUI

struct QuickLookPreview: NSViewRepresentable {
    var url: URL
    
    func makeNSView(context: Context) -> QLPreviewView {
        // Initialize and configure QLPreviewView
        let preview = QLPreviewView()
        preview.previewItem = url as NSURL
        return preview
    }
    
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // Update the view (if needed)
        nsView.previewItem = url as NSURL
    }
}
