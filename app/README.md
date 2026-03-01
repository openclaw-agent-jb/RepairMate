# RepairMate iOS App

An iOS application that provides real-time, AI-powered repair assistance using Google Gemini Live for interactive, two-way voice-guided instructions and safety hazard analysis directly through your device's camera.

## Features

- **Gemini Live AI** — Send real-time video frames and audio to Google Gemini Live for interactive, two-way voice-guided repair assistance
- **Interactive Repair Modes** — Select specific repair domains and procedures to get tailored, context-aware guidance
- **Safety Hazard Analysis** — Real-time automated safety warnings and hazard detection during repair tasks
- **Tool Call Integration** — Delegated tool calls to gather specialized technical data for accurate repair instructions
- **Photo Capture** — Capture high-resolution photos of components or issues during a repair session
- **Device Camera Mode** — Use your iPhone camera to analyze repair tasks and stream visual context to the AI
- **Device compatibility monitoring** — Automatically alerts when the connected glasses need a firmware update

## Architecture

```text
iOS App (DAT SDK) → Device Stream → Gemini Live API (Real-time AI)
```

## Prerequisites

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Meta AI app installed on the same iPhone with **Developer Mode** enabled
- Meta Wearables Developer Center account with a registered app (for `META_WEARABLES_APP_ID` and `META_WEARABLES_CLIENT_TOKEN`)
- Ray-Ban Meta glasses (optional — iPhone camera mode works without glasses)

## Configuration

### Xcode build variables (`ios/Config.xcconfig`)

| Variable                      | Description                                                                         |
| ----------------------------- | ----------------------------------------------------------------------------------- |
| `META_WEARABLES_APP_ID`       | App ID from [Meta Wearables Developer Center](https://wearables.developer.meta.com) |
| `META_WEARABLES_CLIENT_TOKEN` | Client token from Meta Wearables Developer Center (format: `AR\|<app_id>\|<token>`) |

### App Attest (`ios/RepairMate.entitlements`)

The DAT SDK v0.4.0 requires Apple DeviceCheck App Attest. The entitlement is set to `development` by default. Change to `production` before App Store or TestFlight distribution.

## Building and running

```bash
# Open the workspace (not the .xcodeproj)
open ios/RepairMate.xcworkspace
```

Build: `Cmd+B` | Run: `Cmd+R`

## First-time connection setup

1. Install the **Meta AI app** and enable **Developer Mode** (Meta AI app → Settings → Developer Mode)
2. Build and launch RepairMate on your iPhone
3. Tap **Connect My Glasses** — you will be redirected to the Meta AI app to authorize the connection
4. After authorizing, the Meta AI app redirects back to RepairMate
5. Your glasses will appear as a connected device once they are powered on and within Bluetooth range

> **Fresh install note:** If the connection silently fails, open the Meta AI app → Settings → Connected Apps and remove any stale RepairMate entry before retrying.

## Repair Assistance Setup

### Glasses mode

1. Connect your glasses (see above)
2. Start the repair session — the glasses POV feed begins streaming to Gemini Live

### iPhone camera mode

1. Tap **Start on iPhone** — uses the iPhone rear camera instead of the glasses

### Gemini Live AI

Configure your Gemini API settings in the app. When active during a session, Gemini receives video frames and audio and responds via voice with repair guidance.

## Troubleshooting

| Symptom                                           | Fix                                                                                   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------- |
| "Connecting…" reverts with no Meta AI app opening | Check `META_WEARABLES_APP_ID` and `META_WEARABLES_CLIENT_TOKEN` in `Config.xcconfig`  |
| Meta AI app opens but RepairMate doesn't reopen   | Verify `AppLinkURLScheme` is `repairmate://` (with `://`) in `Info.plist`             |
| `DCAppAttestController: Failed to fetch App UUID` | Ensure `com.apple.developer.devicecheck.appattest-environment` entitlement is present |
| Glasses not appearing after registration          | Power on glasses and ensure Bluetooth is enabled and permitted for RepairMate         |

For DAT SDK issues, see the [Meta Wearables developer docs](https://wearables.developer.meta.com/docs/develop/) or the [DAT SDK discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree.
