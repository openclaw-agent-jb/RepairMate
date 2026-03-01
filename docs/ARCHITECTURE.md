# RepairMate — Architecture

## High-Level System Architecture

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'fontFamily': 'sans-serif', 'edgeLabelBackground':'#ffffff'}}}%%
flowchart TB
    classDef userNode fill:#3b82f6,stroke:#2563eb,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef agentNode fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef cloudNode fill:#10b981,stroke:#059669,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef dbNode fill:#f59e0b,stroke:#d97706,stroke-width:2px,color:#fff,rx:8px,ry:8px

    subgraph UserSide ["📱 User Side"]
        GL["👓 Ray-Ban Meta Glasses"]:::userNode
        IP["📱 iPhone Camera fallback"]:::userNode
        MIC["🎙️ User Voice Input"]:::userNode
        EAR["🎧 Glasses Speaker / Headphones"]:::userNode
        IOS["📲 iOS App — RepairMate"]:::userNode
    end

    subgraph Gateway ["🛡️ OpenClaw Agent Gateway"]
        OC["🤖 OpenClaw AI Agent<br/>HTTPS REST — Bearer Auth<br/>x-openclaw-session-key"]:::agentNode
    end

    subgraph GCloud ["☁️ Google Cloud"]
        subgraph GeminiAPI ["🧠 Gemini Live API"]
            GEM["⚡ gemini-2.5-flash-native-audio<br/>Bidirectional WebSocket Stream"]:::cloudNode
        end
        subgraph FirebaseDB ["🔥 Firebase"]
            FS[("🗄️ Firestore<br/>Repair Procedures")]:::dbNode
        end
    end

    GL -->|DAT SDK stream| IOS
    IP -->|AVFoundation stream| IOS
    MIC -->|Audio Input 16 kHz| IOS
    IOS <-->|WSS bidi stream| GEM
    GEM -->|Audio Output 24 kHz| IOS
    IOS --> EAR

    GEM -->|Tool calls: lookup_torque_spec, etc.| IOS
    IOS -->|HTTPS POST /v1/chat/completions| OC
    OC -->|Result| IOS
    IOS -->|Tool result| GEM

    IOS -->|Read procedures| FS
```

---

## Data Flow: Streaming a Repair Session

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'fontFamily': 'sans-serif', 'actorBkg': '#3b82f6', 'actorTextColor': '#ffffff', 'actorBorder': '#2563eb', 'signalColor': '#333333', 'signalTextColor': '#333333', 'noteBkgColor': '#fef08a', 'noteBorderColor': '#eab308'}}}%%
sequenceDiagram
    autonumber
    participant U as 👤 User
    participant G as 👓 Glasses / iPhone
    participant MIC as 🎙️ Microphone
    participant I as 📲 iOS App
    participant GL as 🧠 Gemini Live
    participant OC as 🤖 OpenClaw Agent
    participant FS as 🔥 Firestore

    U->>I: Select Domain (e.g. Automotive)
    U->>I: Select Procedure (e.g. Alternator Replacement)
    I->>FS: Fetch procedure steps, tools, safety info
    FS-->>I: Procedure context

    U->>I: Tap "Stream on Glasses" / "Stream on iPhone"
    G->>I: Video frames (1 fps, JPEG 50%)
    MIC->>I: Audio (16 kHz PCM)
    I-->>GL: WSS bidi stream — audio + video frames + system prompt + procedure context

    GL-->>I: Voice guidance (24 kHz PCM)
    I-->>U: "Disconnect the negative battery terminal first."

    U->>I: "What's the torque spec for the mounting bolt?"
    GL->>I: Function call: lookup_torque_spec(make, model, year, component)
    I->>OC: POST /v1/chat/completions — "Find torque spec for…"
    OC-->>I: "18 Nm / 13 ft-lbs upper mounting bolt"
    I-->>GL: Tool result
    GL-->>I: "That bolt should be torqued to 18 newton-metres."
    I-->>U: (voice)

    Note over I,GL: 🛡️ Safety frame analysis runs every 5s<br/>Alerts user to detected hazards
```

---

## Component Breakdown

| Component                 | Technology                               | Purpose                                                                          |
| ------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------- |
| **Ray-Ban Meta Glasses**  | Meta DAT SDK                             | Primary POV camera + microphone input                                            |
| **iPhone Camera**         | AVFoundation                             | Fallback camera when glasses unavailable                                         |
| **iOS App**               | Swift / SwiftUI                          | Streaming, audio I/O, UI, session orchestration                                  |
| **Gemini Live API**       | `gemini-2.5-flash-native-audio` via WSS  | Bidirectional audio + vision AI assistant                                        |
| **OpenClaw Gateway**      | External HTTPS agent (configurable host) | Executes repair tool lookups — torque specs, wiring diagrams, part compatibility |
| **Firestore**             | Firebase / Google Cloud                  | Read-only repair procedure library (steps, tools, safety warnings)               |
| **TranscriptStore**       | Local on-device (UserDefaults)           | Saves session transcripts for later review                                       |
| **SafetyAnalysisService** | Gemini frame analysis                    | Periodic hazard detection from live video frames                                 |

---

## Deployment Architecture

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'fontFamily': 'sans-serif', 'edgeLabelBackground':'#ffffff'}}}%%
flowchart LR
    classDef deviceNode fill:#3b82f6,stroke:#2563eb,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef externalNode fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef cloudNode fill:#10b981,stroke:#059669,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef dbNode fill:#f59e0b,stroke:#d97706,stroke-width:2px,color:#fff,rx:8px,ry:8px

    subgraph OnDevice ["📱 On-Device"]
        IOS["📲 iOS App"]:::deviceNode
        GL["👓 Ray-Ban Glasses<br/>via DAT SDK BT"]:::deviceNode
        IP["📷 iPhone Camera<br/>AVFoundation"]:::deviceNode
        TS[("💾 TranscriptStore<br/>Local")]:::dbNode
    end

    subgraph External ["🔌 External — Configurable"]
        OC["🤖 OpenClaw Agent Gateway<br/>HTTPS + Bearer Token"]:::externalNode
    end

    subgraph GCloud ["☁️ Google Cloud"]
        GEM["🧠 Gemini Live API<br/>generativelanguage.googleapis.com<br/>WSS Bidi Stream"]:::cloudNode
        FS[("🔥 Firestore<br/>Repair Procedures")]:::dbNode
    end

    GL -->|Bluetooth RTMP| IOS
    IP -->|AVCaptureSession| IOS
    IOS <-->|WSS — audio + frames| GEM
    IOS -->|HTTPS POST| OC
    OC -->|Tool results| IOS
    IOS -->|SDK read| FS
    IOS -->|Write| TS
```

> **No Cloud Run or Load Balancer.** The iOS app connects directly to the Gemini Live API via a secure WebSocket. OpenClaw is a separately hosted agent gateway accessed over HTTPS, not a cloud-managed service deployed with this app.

---

## RepairMate Tool Calls (via OpenClaw)

Gemini triggers these when it needs domain-specific data during a repair session. The iOS app proxies each call to OpenClaw and returns the result to Gemini as a function result.

| Tool                       | Trigger                                         | Args                                        |
| -------------------------- | ----------------------------------------------- | ------------------------------------------- |
| `lookup_torque_spec`       | User needs exact torque value during reassembly | make, model, year, component, bolt_location |
| `lookup_wiring_diagram`    | User confused about electrical connections      | system, make, model, year                   |
| `check_part_compatibility` | User has a part number or unsure if part fits   | part_number, make, model, year              |

---

## Security

| Concern                | Implementation                                                   |
| ---------------------- | ---------------------------------------------------------------- |
| **Gemini API Key**     | Stored in iOS Keychain; read at runtime — never compiled in      |
| **OpenClaw Token**     | Bearer token stored in Keychain; sent as `Authorization` header  |
| **Session continuity** | `x-openclaw-session-key` header (rotating ISO8601 timestamp key) |
| **Transport**          | WSS (Gemini) + TLS HTTPS (OpenClaw + Firestore)                  |

---

## Tech Stack Summary

| Layer              | Technology                                            |
| ------------------ | ----------------------------------------------------- |
| **Mobile**         | Swift, SwiftUI, Combine                               |
| **AI / Vision**    | Gemini 2.5 Flash Native Audio (bidi WSS)              |
| **Tool Execution** | OpenClaw Agent Gateway (HTTPS REST)                   |
| **Data**           | Firestore (procedures), UserDefaults (transcripts)    |
| **Hardware**       | Ray-Ban Meta AI Glasses (DAT SDK), iPhone camera      |
| **Protocol**       | WebSocket bidi stream (Gemini), HTTPS POST (OpenClaw) |
