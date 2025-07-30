Developer Documentation

## Custom Action List

Configurable in "Settings - Applications".

The configuration file is located at `Library/Application Support/Selected/UserConfiguration.json`.

Example content:

```json
{
  "appConditions": [
    {
      "bundleID": "com.apple.dt.Xcode",
      "actions": ["selected.websearch", "selected.xcode.format"]
    }
  ]
}
```

`appConditions.bundleID` is the bundle ID of the application.
`actions` is a list of `action.identifier`.

For details on available actions and how to customize them, please refer to Built-in Actions and Custom Plugins.

If no action list is configured for an application, or if the configured action list is empty, all available actions will be displayed.
