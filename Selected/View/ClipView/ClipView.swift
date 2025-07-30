//
//  ClipView.swift
//  Selected
//
//  Created by sake on 2024/4/7.
//

import Foundation
import SwiftUI
import PDFKit

struct ClipDataView: View {
    var data: ClipHistoryData

    var body: some View {
        VStack(alignment: .leading){
            let item = data.getItems().first!
            let type = NSPasteboard.PasteboardType(item.type!)
            if type == .png {
                Image(nsImage: NSImage(data: item.data!)!).resizable().aspectRatio(contentMode: .fit)
            } else if type == .rtf {
                RTFView(rtfData: item.data!)
            } else if type == .fileURL {
                let url = URL(string: String(decoding: item.data!, as: UTF8.self))!
                let name = url.lastPathComponent.removingPercentEncoding!
                if name.hasSuffix(".pdf") {
                    PDFKitRepresentedView(url: url)
                } else {
                    QuickLookPreview(url: url)
                }
            } else if data.plainText != nil {
                TextView(text: data.plainText!)
            }

            Spacer()
            Divider()

            HStack {
                Text("Application:")
                Spacer()
                getIcon(data.application!)
                Text(getAppName(data.application!))
            }.frame(height: 17)

            HStack {
                Text("Content type:")
                Spacer()
                if let text = data.plainText, isValidHttpUrl(text) {
                    Text("Link")
                } else {
                    let str = "\(type)"
                    Text(NSLocalizedString(str, comment: ""))
                }
            }.frame(height: 17)

            HStack {
                Text("Date:")
                Spacer()
                Text("\(format(data.firstCopiedAt!))")
            }.frame(height: 17)

            if data.numberOfCopies > 1 {
                HStack {
                    Text("Last copied:")
                    Spacer()
                    Text("\(format(data.lastCopiedAt!))")
                }.frame(height: 17)
                HStack {
                    Text("Copied:")
                    Spacer()
                    Text("\(data.numberOfCopies) times")
                }.frame(height: 17)
            }

            if let url = data.url {
                if type == .fileURL {
                    let url = URL(string: String(decoding: item.data!, as: UTF8.self))!
                    HStack {
                        Text("Path:")
                        Spacer()
                        Text(url.path().removingPercentEncoding!).lineLimit(1)
                    }.frame(height: 17)
                } else {
                    HStack {
                        Text("URL:")
                        Spacer()
                        Link(destination: URL(string: url)!, label: {
                            Text(url).lineLimit(1)
                        })
                    }.frame(height: 17)
                }
            }
        }.padding().frame(width: 550)
    }

    private func getAppName(_ bundleID: String) -> String {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "Unknown"
        }
        return FileManager.default.displayName(atPath: bundleURL.path)
    }

    private func getIcon(_ bundleID: String) -> some View {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else{
            return AnyView(EmptyView())
        }
        return AnyView(
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path)).resizable().aspectRatio(contentMode: .fit).frame(width: 15, height: 15)
        )
    }
}

func format(_ d: Date) -> String{
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short
    return dateFormatter.string(from: d)
}

func isValidHttpUrl(_ string: String) -> Bool {
    guard let url = URL(string: string) else {
        return false
    }

    guard let scheme = url.scheme, scheme == "http" || scheme == "https" else {
        return false
    }

    return url.host != nil
}


class ClipViewModel: ObservableObject {
    static let shared = ClipViewModel()
    @Published var selectedItem: ClipHistoryData?
}


// MARK: - Clipboard Item Row (Displays different content based on clipboard data type)
struct ClipRowView: View {
    let clip: ClipHistoryData

    var body: some View {
        // Get the first item from clip
        if let item = clip.getItems().first, let typeString = item.type{
            let type = NSPasteboard.PasteboardType(rawValue: typeString)
            switch type {
                case .png:
                    if let data = item.data, let image = NSImage(data: data) {
                        let widthStr = valueFormatter.string(from: NSNumber(value: Double(image.size.width))) ?? ""
                        let heightStr = valueFormatter.string(from: NSNumber(value: Double(image.size.height))) ?? ""
                        return AnyView(Label(
                            title: { Text("Image \(widthStr) * \(heightStr)").padding(.leading, 10) },
                            icon: { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                case .fileURL:
                    if let data = item.data,
                       let url = URL(string: String(decoding: data, as: UTF8.self)) {
                        return AnyView(Label(
                            title: { Text(url.lastPathComponent.removingPercentEncoding ?? "").lineLimit(1).padding(.leading, 10) },
                            icon: { Image(systemName: "doc.on.doc").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                case .rtf:
                    if let plainText = clip.plainText {
                        return AnyView(Label(
                            title: { Text(plainText.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(1).padding(.leading, 10) },
                            icon: { Image(systemName: "doc.richtext").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                case .string:
                    if let plainText = clip.plainText {
                        return AnyView(Label(
                            title: { Text(plainText.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(1).padding(.leading, 10) },
                            icon: { Image(systemName: "doc.plaintext").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                case .html:
                    if let plainText = clip.plainText {
                        return AnyView(Label(
                            title: { Text(plainText.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(1).padding(.leading, 10) },
                            icon: { Image(systemName: "circle.dashed.rectangle").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                case .URL:
                    if let urlString = clip.url {
                        return AnyView(Label(
                            title: { Text(urlString.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(1).padding(.leading, 10) },
                            icon: { Image(systemName: "link").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20) }
                        ))
                    }
                default:
                    break
            }
        }
        return AnyView(EmptyView())
    }
}

struct ClipView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ClipHistoryData.lastCopiedAt, ascending: false)],
        animation: .default)
    private var clips: FetchedResults<ClipHistoryData>

    @ObservedObject var viewModel = ClipViewModel.shared
    @FocusState private var isFocused: Bool

    // Add search state
    @State private var searchText = ""

    // Add computed property for filtered results
    private var filteredClips: [ClipHistoryData] {
        if searchText.isEmpty {
            return Array(clips)
        } else {
            return clips.filter { clip in
                // Search plain text content
                if let plainText = clip.plainText, plainText.localizedCaseInsensitiveContains(searchText) {
                    return true
                }

                // Search URL
                if let url = clip.url, url.localizedCaseInsensitiveContains(searchText) {
                    return true
                }

                // If it's a file, search the filename
                if let item = clip.getItems().first,
                   let type = item.type,
                   NSPasteboard.PasteboardType(type) == .fileURL,
                   let data = item.data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString),
                   url.lastPathComponent.localizedCaseInsensitiveContains(searchText) {
                    return true
                }

                return false
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                SearchBarView(searchText: $searchText, onArrowKey: handleArrowKey)

                if filteredClips.isEmpty {
                    Text(searchText.isEmpty ? "Clipboard History" : "No results found")
                        .frame(width: 250)
                        .padding(.top)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        List(filteredClips, id: \.self, selection: $viewModel.selectedItem) { clipData in
                            NavigationLink(destination: ClipDataView(data: clipData), tag: clipData, selection: $viewModel.selectedItem) {
                                ClipRowView(clip: clipData)
                            }
                            .frame(height: 30)
                            .contextMenu {
                                Button(action: {
                                    delete(clipData)
                                }){
                                    Text("Delete")
                                }
                            }
                        }
                        .frame(width: 250)
                        .frame(minWidth: 250, maxWidth: 250)
                        // When search text changes, default to selecting the first item and scrolling to the top
                        .onChange(of: searchText) { _ in
                            if !filteredClips.isEmpty {
                                viewModel.selectedItem = filteredClips.first
                                withAnimation {
                                    proxy.scrollTo(filteredClips.first, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.selectedItem = clips.first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isFocused = true
                }
            }
            .focused($isFocused)
        }
        .frame(width: 800, height: 400)
    }

    // MARK: - Handle arrow key events to update selected item
    private func handleArrowKey(_ direction: CustomSearchField.ArrowDirection) {
        guard !filteredClips.isEmpty else { return }
        if direction == .down {
            if let current = viewModel.selectedItem,
               let index = filteredClips.firstIndex(of: current),
               index < filteredClips.count - 1 {
                viewModel.selectedItem = filteredClips[index + 1]
            } else {
                viewModel.selectedItem = filteredClips.first
            }
        } else if direction == .up {
            if let current = viewModel.selectedItem,
               let index = filteredClips.firstIndex(of: current),
               index > 0 {
                viewModel.selectedItem = filteredClips[index - 1]
            }
        }
    }

    // MARK: - Delete clipboard item and update selection status
    func delete(_ clipData: ClipHistoryData) {
        if let selectedItem = viewModel.selectedItem {
            let selectedItemIdx = filteredClips.firstIndex(of: selectedItem) ?? 0
            let idx = filteredClips.firstIndex(of: clipData) ?? 0

            // Calculate the index of the new item to be selected after deletion
            let newIndexAfterDeletion: Int?
            if selectedItem == clipData {
                if filteredClips.count > idx + 1 {
                    newIndexAfterDeletion = idx // Select next
                } else if idx > 0 {
                    newIndexAfterDeletion = idx - 1 // Select previous
                } else {
                    newIndexAfterDeletion = nil // No other items to select
                }
            } else if idx < selectedItemIdx {
                newIndexAfterDeletion = selectedItemIdx > 0 ? selectedItemIdx - 1 : 0
            } else {
                newIndexAfterDeletion = selectedItemIdx
            }

            PersistenceController.shared.delete(item: clipData)

            // Update selected item after deletion
            DispatchQueue.main.async {
                if let newIndex = newIndexAfterDeletion, filteredClips.indices.contains(newIndex) {
                    viewModel.selectedItem = filteredClips[newIndex]
                } else if !filteredClips.isEmpty {
                    viewModel.selectedItem = filteredClips.first
                } else {
                    viewModel.selectedItem = nil
                }
            }
        }
    }
}

#Preview {
    ClipView()
}
