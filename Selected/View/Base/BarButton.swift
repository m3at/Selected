//
//  BarButton.swift
//  Selected
//
//  Created by sake on 2024/3/11.
//

import SwiftUI

extension String {
    func trimPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}

struct BarButton: View {
    var icon: String
    var title: String
    var clicked: ((_: Binding<Bool>) -> Void) /// use closure for callback
    
    @State private var shouldPopover: Bool = false
    @State private var hoverWorkItem: DispatchWorkItem?
    
    @State private var isLoading = false
    
    
    var body: some View {
        Button {
            DispatchQueue.main.async {
                clicked($isLoading)
                NSLog("isLoading \(isLoading)")
            }
        } label: {
            ZStack {
                HStack{
                    Icon(icon)
                }.frame(width: 40, height: 30).opacity(isLoading ? 0.5 : 1)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        .scaleEffect(0.5, anchor: .center) // Adjust size and position as needed
                }
            }
        }.frame(width: 40, height: 30)
            .buttonStyle(BarButtonStyle()).onHover(perform: { hovering in
                hoverWorkItem?.cancel()
                if title.count == 0 {
                    shouldPopover = false
                    return
                }
                if !hovering{
                    shouldPopover = false
                    return
                }
                
                let workItem = DispatchWorkItem {
                    shouldPopover = hovering
                }
                hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
            })
            .popover(isPresented: $shouldPopover, content: {
                // Add interactiveDismissDisabled.
                // Otherwise, when a popover is present, you need to click an action to dismiss the popover and then click again to trigger the onclick event.
                Text(title).font(.headline).padding(5).interactiveDismissDisabled()
            })
    }
}

// BarButtonStyle: Display different colors for click and onHover
struct BarButtonStyle: ButtonStyle {
    @State var isHover = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(getColor(isPressed: configuration.isPressed))
            .foregroundColor(.white)
            .onHover(perform: { hovering in
                isHover = hovering
            })
    }
    
    func getColor(isPressed: Bool) -> Color{
        if isPressed {
            return .blue.opacity(0.4)
        }
        return isHover ? .blue : .gray
    }
}
