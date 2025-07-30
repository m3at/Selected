//
//  RTFView.swift
//  Selected
//
//  Created by sake on 2024/4/7.
//

import Foundation
import SwiftUI

struct RTFView: NSViewRepresentable {
    var rtfData: Data
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false // Set to false to disable editing
        textView.autoresizingMask = [.width]
        textView.translatesAutoresizingMaskIntoConstraints = true
        if let attributedString =
            try? NSMutableAttributedString(data: rtfData,
                                           options: [
                                            .documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil) {
            let originalRange = NSMakeRange(0, attributedString.length);
            attributedString.addAttribute(NSAttributedString.Key.backgroundColor,  value: NSColor.clear, range: originalRange)
            
            textView.textStorage?.setAttributedString(attributedString)
        }
        textView.drawsBackground = false // Ensure no default background is drawn
        textView.backgroundColor = .clear
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false // Ensure no default background is drawn
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Used to update the view
    }
}
