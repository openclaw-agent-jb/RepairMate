# RepairMate

**A hands-on technical repair assistant powered by Gemini Live API.**

RepairMate is an iOS app that provides real-time, voice-guided repair instructions using the Gemini Live API's bidirectional streaming capabilities (audio + vision). Stream POV video from your camera while receiving step-by-step guidance, safety checks, and answers to interruptible questions like _"Which bolt first?"_ or _"Is this safe?"_

---

## Overview

**The Problem:** You can't consult manuals or watch videos while your hands are busy fixing things.

**The Solution:** RepairMate streams your camera feed to Gemini Live, which analyzes what you're seeing and provides voice-guided instructions through your headphones. The app includes pre-loaded repair procedures with tools, safety warnings, and visual cues, creating a hands-free repair assistant.

### Sample Interaction

> **User:** _"I'm replacing the alternator"_
> **Guide:** _"First, disconnect the negative battery terminal. That's the black cable with the minus sign."_
> **User:** _"Which bolt do I loosen first?"_
> **Guide:** _"The top 12mm mounting bolt, closest to the windshield."_

---

## Repository Structure

```
RepairMate/
├── app/                    # iOS app (Swift/SwiftUI)
│   ├── RepairMate/         # Main app source code
│   │   ├── Views/          # SwiftUI views and components
│   │   ├── ViewModels/     # MVVM state management
│   │   ├── Services/       # API clients, Firestore, OpenClaw
│   │   ├── Utils/          # Utilities (PixelBuffer, Time)
│   │   └── Assets.xcassets/ # Images and color assets
│   ├── RepairMateTests/    # Unit and integration tests
│   ├── RepairMate.xcodeproj/
│   └── README.md           # iOS app documentation
├── backend/                # Firebase backend
│   ├── import-procedures.js  # Firestore data importer
│   ├── data/procedures.json  # Repair procedure seed data
│   ├── firestore.rules     # Database security rules
│   ├── firebase.json         # Firebase configuration
│   └── README.md             # Backend setup guide
└── docs/                   # Project documentation
    └── CHALLENGE_GUIDE.md  # Complete technical specification
```

---

## Tech Stack

| Layer       | Technology                                           |
| ----------- | ---------------------------------------------------- |
| **Mobile**  | Swift, SwiftUI, Combine                              |
| **AI/ML**   | Gemini Live API (Vertex AI), bidirectional streaming |
| **Storage** | Firestore (procedures, workflows)                    |
| **Gateway** | OpenClaw WebSocket bridge                            |
| **Testing** | XCTest with custom stubs and mocks                   |

---

## Architecture

High-level data flow:

```
┌─────────────────┐      RTMP       ┌─────────┐     WebSocket    ┌──────────┐
│   Camera Feed   │ ───────────────→│ iOS App │ ────────────────→│ OpenClaw │
│ (iPhone Camera)│                 │         │                  │ (Bridge) │
└─────────────────┘                 └─────────┘                  └────┬─────┘
                                                                    │
                                                                    │ (HTTPS)
                                                                    ↓
┌─────────────┐                                             ┌──────────────┐
│  Audio Out   │ ←────────────────────────────────────────── │  Vertex AI   │
│ (Headphones) │         Gemini Live API (bidi stream)       │ Gemini Live  │
└─────────────┘                                             └──────┬───────┘
                                                                   │
                                    ┌──────────────┬───────────────┴────────┐
                                    ↓              ↓                      ↓
                             ┌────────────┐  ┌──────────┐         ┌──────────┐
                             │ Firestore  │  │  Vision  │         │   RAG    │
                             │(Procedures)│  │   OCR    │         │ (Vector) │
                             └────────────┘  └──────────┘         └──────────┘
```

### Component Breakdown

**iOS App (Swift/SwiftUI)**

- `StreamSessionViewModel` — Manages WebSocket connection to OpenClaw
- `GeminiSessionViewModel` — Handles Gemini Live API session lifecycle
- `WearablesViewModel` — Manages camera streaming and audio routing
- `FirestoreService` — Fetches repair procedures from Firestore

**OpenClaw Gateway**

- WebSocket server that bridges iOS client to Gemini Live API
- Handles audio/video frame forwarding
- Manages session lifecycle

**Firebase Backend**

- **procedures** — Read-only repair guides (alternator, brakes, plumbing, etc.)
- **workflows** — User-specific session data
- **safetyLogs** — Safety event logging

---

## Quick Start

### Prerequisites

- macOS with Xcode 15.0+
- iOS 17.0+ device or simulator
- Google Cloud project with Vertex AI enabled
- OpenClaw gateway running locally (optional, for development)

### 1. iOS App Setup

```bash
cd app
open RepairMate.xcodeproj
```

Build and run from Xcode. See `app/README.md` for detailed setup.

### 2. Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Configure Firebase (update .firebaserc with your project)
firebase login

# Import sample procedures
npm run import
```

See `backend/README.md` for complete Firebase setup instructions.

### 3. Configure API Keys

Create `app/Config.xcconfig` with your Gemini API key:

```
GEMINI_API_KEY=your_api_key_here
```

---

## Key Features

| Feature                  | Description                                                    |
| ------------------------ | -------------------------------------------------------------- |
| **Bidirectional Stream** | Audio + video streaming to Gemini Live                         |
| **Voice Commands**       | Interruptible queries (_"What am I looking at?"_)              |
| **Procedure Library**    | Pre-loaded repair guides with tools, steps, safety info        |
| **Safety Check**         | Frame analysis every 5 seconds for hazard detection            |
| **Visual Cues**          | Descriptions of what to look for (_"Black cable, minus sign"_) |

---

## Documentation

| Document                                             | Description                      |
| ---------------------------------------------------- | -------------------------------- |
| [`app/README.md`](app/README.md)                     | iOS app architecture and setup   |
| [`backend/README.md`](backend/README.md)             | Firebase setup and import script |
| [`docs/CHALLENGE_GUIDE.md`](docs/CHALLENGE_GUIDE.md) | Complete technical specification |

---

## Testing

Run unit tests from Xcode or command line:

```bash
cd app
xcodebuild test -project RepairMate.xcodeproj -scheme RepairMate -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Requirements

| Requirement         | Implementation                                |
| ------------------- | --------------------------------------------- |
| **Gemini Live API** | Bidirectional streaming (audio + vision)      |
| **Multimodal**      | Video frames + audio streaming simultaneously |
| **Interruptible**   | Natural conversation flow with query handling |
| **Cloud Deploy**    | Firebase Firestore for data persistence       |

---

## License

This project was created for the Gemini Live Agent Challenge.

See the [LICENSE.md](LICENSE.md) file for licensing details.

---

_Created for the Gemini Live Agent Challenge 2026_
