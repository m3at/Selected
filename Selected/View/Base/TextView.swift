//
//  TextView.swift
//  Selected
//
//  Created by sake on 2024/4/18.
//

import SwiftUI
import AppKit

struct TextView: NSViewRepresentable {
    var text: String
    var font: NSFont? = NSFont(name: "UbuntuMonoNFM", size: 14)
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false // Ensure no default background is drawn
        
        // Configure text view
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.string = text
        textView.font = font
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
    }
}
