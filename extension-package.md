If it is a custom extension, first create a unique Uniform Type Identifier (UTI) for the extension and then register it with the system. Then, the default application can be set using the same method. This usually requires adding relevant key-value pairs to the application's Info.plist file to declare custom file types (UTIs).

Here are the steps based on custom extension names:

<img src="DocImages/info-uti.png" alt="info-uti" style="zoom:50%;" />

**Step 1: Define Custom Extension in Info.plist**

1. Open the application's Info.plist file.
2. Add a new key `CFBundleDocumentTypes` (if it doesn't exist).
3. Under `CFBundleDocumentTypes`, add a new dictionary to define `CFBundleTypeName` and `CFBundleTypeExtensions` for the custom extension.
4. If you need to register a directory as a package, you need to configure `LSTypeIsPackage` to `true`.

```plist
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeExtensions</key>
    <array>
      <string>Custom extension, without the dot.</string>
    </array>
    <key>CFBundleTypeIconFile</key>
    <string>IconFileName</string>
    <key>CFBundleTypeName</key>
    <string>Custom File Type Name</string>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>LSHandlerRank</key>
    <string>Owner</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>Custom UTI</string>
    </array>
  </dict>
</array>
```

There is a problem here: as soon as I configure `LSItemContentTypes`, it cannot be used. If I remove it, a custom UTI directory or file can be opened normally.

**Step 2: Register Custom UTI**

You also need to register the UTI in Info.plist.

```plist
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeConformsTo</key>
    <array>
      <string>public.data</string>
      <string>public.folder</string>
    </array>
    <key>UTTypeDescription</key>
    <string>Custom File Type Description</string>
    <key>UTTypeIdentifier</key>
    <string>Custom UTI</string>
    <key>UTTypeSize320IconFile</key>
    <string>MyIcon.png</string>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <string>Custom extension, without the dot.</string>
    </dict>
  </dict>
</array>
```

Then you can set the default application using Swift code and use the registered custom UTI.

```swift
import SwiftUI
import AppKit

func setDefaultAppForCustomFileType() {
  let customUTI = "Custom UTI" // Replace with your custom UTI
  let bundleIdentifier = "your.app.bundle.identifier" // Replace with your app's bundle identifier
  LSSetDefaultRoleHandlerForContentType(customUTI as CFString, .editor, bundleIdentifier as CFString)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setDefaultAppForCustomFileType()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Handle opened files
            NSLog("\(url.path)")   
        }
    }
}


// App entry point
@main
struct ShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { ... }
}
```
