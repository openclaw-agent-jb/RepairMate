# RepairMate — Hands-On Technical Assistant

## Category 1: Live Agents 🗣️

**Concept:** A voice-activated, vision-guided technical assistant that sees what you're fixing and provides step-by-step repair instructions via audio.

---

## Problem Statement

When fixing things, your hands are busy and your eyes are occupied. You can't:

- Scroll through PDF manuals
- Watch YouTube tutorials while working
- Type queries into a phone
- Read error codes on equipment

**RepairMate solves this** by:

- Seeing through your glasses what you're looking at
- Speaking instructions directly to your ear
- Understanding your voice questions mid-task
- Handling interruptions naturally
- Warning about safety issues in real-time

---

## Use Cases & Scenarios

### Scenario 1: Car Engine Repair

**User:** Home mechanic working on a 2015 Honda Civic

**Flow:**

1. User opens hood and looks at engine bay
2. _"Hey RepairMate, I'm replacing the alternator"_
3. **RepairMate:** _"Got it. I see the alternator on the left side. First, disconnect the negative battery terminal. That's the black cable with the minus sign."_
4. User works, then asks: _"Wait, which bolt do I loosen first?"_
5. **RepairMate:** _"The top 12mm mounting bolt. It's the one closest to the windshield. Don't touch the bottom one yet."_
6. User attempts, then: _"This one's stuck"_
7. **RepairMate:** _"Apply penetrating oil and let it sit 5 minutes. Meanwhile, disconnect the electrical connector—it's the plug with the red tab on top."_

**Safety Check:**

- _"Stop—I see a battery cable still connected. Disconnect that first before touching metal tools to the alternator."_

---

### Scenario 2: Circuit Board Repair

**User:** Electronics hobbyist fixing a vintage amplifier

**Flow:**

1. User points glasses at circuit board
2. _"What's this component?"_
3. **RepairMate:** _"That's a 470µF electrolytic capacitor. I can see it's bulging at the top—that's a failure sign. You should replace it."_
4. _"What do I need?"_
5. **RepairMate:** _"470µF, 50V minimum rating. Looks like it's 105°C rated based on the markings. Desolder the two legs first."_
6. User solders, asks: _"Is this the right way around?"_
7. **RepairMate:** _"Yes—striped side is negative, that goes to the side with the black half-moon marking on the PCB."_

**Safety Check:**

- _"Make sure the capacitor is fully discharged. Don't touch both legs at once."_

---

### Scenario 3: Appliance Repair (Washing Machine)

**User:** DIY homeowner fixing a leaking washer

**Flow:**

1. _"My washing machine is leaking from the bottom"_
2. **RepairMate:** _"Let me see. Can you tilt the machine back slightly? ... I see water pooling under the drain pump. That's a common failure point."_
3. _"How do I check it?"_
4. **RepairMate:** _"There's a circular access panel on the front bottom right. Remove that with a Phillips head. The pump filter is behind it—turn it counterclockwise. Have a towel ready."_
5. User removes, finds blockage
6. **RepairMate:** _"That sock was blocking the impeller. Clear it out and screw the filter back in hand-tight only."_

**Safety Check:**

- _"Unplug the machine from the wall before accessing the pump. Water and electricity don't mix."_

---

### Scenario 4: HVAC Troubleshooting

**User:** Maintenance tech diagnosing an AC unit

**Flow:**

1. User points at thermostat wiring
2. _"This AC isn't cooling"_
3. **RepairMate:** _"I see the thermostat wiring. R, W, Y, G are all connected. Can you show me the outdoor unit?"_
4. User walks outside
5. **RepairMate:** _"The contactor isn't pulling in. That's likely low voltage. Check the breaker first."_
6. _"Breaker is on"_
7. **RepairMate:** _"Check the low voltage fuse on the control board inside. It's usually a 3 amp blade fuse near the transformer."_
8. User finds blown fuse
9. **RepairMate:** _"Replace it, but check the wiring for shorts first—a blown fuse usually means something else is wrong. Look for bare wires touching metal."_

---

## Technical Implementation

```
┌─────────────────────────────────────────────────────────────┐
│                    EXPERT MODE SYSTEM                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User Input → Domain Selection (Car/Electronics/HVAC/etc)  │
│                      ↓                                       │
│  RAG Context Load → Vector DB Query (specific domain)       │
│                      ↓                                       │
│  System Prompt Injection (domain-specific instructions)     │
│                      ↓                                       │
│  Gemini Live API with domain context                        │
│                      ↓                                       │
│  Tool Access (web search, manual lookup, parts catalog)     │
└─────────────────────────────────────────────────────────────┘
```

### New Components

| Component             | Technology                | Purpose                          |
| --------------------- | ------------------------- | -------------------------------- |
| **Domain Selector**   | SwiftUI Dropdown          | User selects repair category     |
| **RAG Vector Store**  | Vertex AI Matching Engine | Domain-specific repair knowledge |
| **Safety Classifier** | Gemini Flash              | Real-time safety risk detection  |
| **Parts Lookup Tool** | Web Search + API          | Find specs, compatibility        |
| **Workflow Tracker**  | Firestore                 | Track multi-step procedures      |

### Domain Catalog Structure

```json
{
  "domains": {
    "auto_repair": {
      "system_prompt": "You are an ASE-certified mechanic...",
      "rag_collection": "automotive_procedures",
      "safety_rules": [
        "battery_disconnection",
        "jack_stand_usage",
        "hot_engine_warning"
      ],
      "tools": [
        "torque_specs_lookup",
        "wiring_diagram_search",
        "recall_checker"
      ],
      "common_procedures": [
        "brake_pad_replacement",
        "oil_change",
        "alternator_replacement"
      ]
    },
    "electronics_repair": {
      "system_prompt": "You are an electronics technician...",
      "rag_collection": "electronics_repair",
      "safety_rules": [
        "capacitor_discharge",
        "esd_precautions",
        "high_voltage_warning"
      ],
      "tools": ["component_identifier", "datasheet_lookup", "schematic_search"]
    },
    "appliance_repair": {
      "system_prompt": "You are an appliance repair technician...",
      "rag_collection": "appliance_manuals",
      "safety_rules": [
        "unplug_first",
        "water_electricity",
        "gas_leak_detection"
      ]
    },
    "hvac": {
      "system_prompt": "You are an HVAC technician...",
      "rag_collection": "hvac_troubleshooting",
      "safety_rules": [
        "refrigerant_handling",
        "electrical_safety",
        "gas_systems"
      ]
    }
  }
}
```

### RAG Document Structure

Each procedure document contains:

```markdown
# Procedure: Alternator Replacement - 2015 Honda Civic

## Metadata

- **Domain:** auto_repair
- **Difficulty:** Intermediate
- **Time:** 45-60 minutes
- **Tools:** 10mm, 12mm, 14mm sockets, ratchet, extensions
- **Safety:** ["battery_disconnect", "hot_engine"]

## Step-by-Step

### Step 1: Safety Preparation

**Action:** Disconnect negative battery terminal
**Visual Cues:** Black cable, minus sign, 10mm nut
**Safety Warning:** Prevents short circuits when removing alternator

### Step 2: Access

**Action:** Remove engine cover (if present)
**Visual Cues:** Plastic clips, pull up firmly

### Step 3: Electrical Disconnect

**Action:** Unplug alternator connector
**Visual Cues:** Push tab on top, pull straight out
**Common Issue:** Tab breaks—use flathead if stuck

### Step 4: Remove Belt

**Action:** Loosen tensioner, slip belt off alternator pulley
**Visual Cues:** 14mm bolt on tensioner arm, rotate clockwise
**Safety:** Engine can be hot—wear gloves

### Step 5: Mounting Bolts

**Action:** Remove 12mm top and bottom bolts
**Visual Cues:** Two bolts, one near windshield, one near radiator
**Sequence:** Top first, then bottom
**Torque Spec:** Top: 47 Nm, Bottom: 47 Nm (reassembly)

### Step 6: Remove Alternator

**Action:** Work alternator out of bracket
**Visual Cues:** May need to tilt, watch for coolant lines

### Step 7: Installation (Reverse)

**Action:** Reverse steps 6-1
**Critical:** Torque bolts to spec, don't overtighten
**Test:** Start engine, check voltage at battery (13.8-14.4V)

## Common Mistakes

1. Forgetting to disconnect battery (sparks)
2. Dropping bolt into engine bay (use magnetic tray)
3. Overtightening bolts (stripped threads)

## Visual References

[Diagram showing alternator location in engine bay]
[Photo of electrical connector with arrow pointing to release tab]
```

---

## Gemini Live API Integration

### System Prompt Template

```
You are RepairMate, an expert technical assistant helping with hands-on repairs.
The user is wearing camera glasses and will ask questions about what they're seeing.

DOMAIN: {domain}
EXPERTISE LEVEL: {beginner/intermediate/advanced}

CAPABILITIES:
- Identify components and parts visually
- step-by-step procedures
- Answer interrupting questions naturally
- Warn about safety issues immediately
- Look up specs, torques, compatibility
- Troubleshoot when things go wrong

SAFETY RULES (always enforce):
{domain_safety_rules}

WORKFLOW STYLE:
1. Give ONE step at a time unless asked for overview
2. Wait for user confirmation before proceeding
3. Be specific about visual cues (colors, shapes, positions)
4. Use approximate sizes ("about the size of a deck of cards")
5. Warn BEFORE user acts on dangerous steps

INTERRUPTION HANDLING:
When user interrupts with a question:
- Pause current instruction
- Answer the question fully
- Ask "Should I continue with the repair?" or resume automatically

TOOLS AVAILABLE:
- web_search: For specs, compatibility, error codes
- fetch: For manual pages, wiring diagrams
- message: Send critical alerts to user's phone

SPEAK IN SHORT, CLEAR SENTENCES. The user is working with their hands.
```

### Example Bidi Stream Session

```javascript
// Connection established
{
  "role": "user",
  "parts": [{"text": "I'm replacing the alternator on a 2015 Honda Civic"}]
}

// Gemini responds with voice
{
  "role": "model",
  "parts": [{"text": "Got it. First things first—disconnect the negative battery terminal. That's the black cable with the minus sign. Do you see it?"}]
}

// User asks interrupting question
{
  "role": "user",
  "parts": [{"text": "Wait, which bolt is the alternator mounted with?"}]
}

// Gemini answers, then returns to flow
{
  "role": "model",
  "parts": [{"text": "Two 12mm bolts—one near the windshield, one near the radiator. You'll remove those in step 4. First, disconnect that battery. See the black cable?"}]
}

// User confirms
{
  "role": "user",
  "parts": [{"text": "Done"}]
}

// Gemini continues
{
  "role": "model",
  "parts": [{"text": "Good. Now remove the engine cover if there's one. Look for plastic clips—pull up firmly. Next step is unplugging the alternator connector."}]
}

// Vision analysis happens in parallel
{
  "role": "user",
  "parts": [{"inline_data": {"mime_type": "image/jpeg", "data": "...base64..."}}]
}
```

---

## Safety Features

### Real-Time Safety Detection

```javascript
// Safety classifier runs on every frame
async function checkSafety(frame, currentStep) {
  const safetyPrompt = `
    Analyze this image for safety hazards:
    - Is the user about to touch something dangerous?
    - Are safety procedures being followed?
    - Current task: ${currentStep}
    
    Respond with: SAFE, WARNING: [reason], or STOP: [critical danger]
  `;

  const result = await gemini.classify({ image: frame, prompt: safetyPrompt });

  if (result.startsWith("STOP")) {
    await speakImmediately(result); // Interrupt any ongoing speech
    await sendPhoneAlert(result); // Backup notification
  }
}
```

### Safety Categories by Domain

| Domain          | Critical Warnings                                  | Common Mistakes                    |
| --------------- | -------------------------------------------------- | ---------------------------------- |
| **Auto**        | Battery connected, hot engine, unsupported vehicle | Wrong bolt order, lost fasteners   |
| **Electronics** | Charged capacitors, live circuits, ESD             | Wrong polarity, overheating iron   |
| **Appliance**   | Water + electricity, gas leaks, moving parts       | Not unplugging, improper grounding |
| **HVAC**        | Refrigerant exposure, high voltage, gas systems    | Overcharging, wiring errors        |

### Emergency Stop

User can say:

- _"Stop"_ — Pause all instructions
- _"Emergency"_ — Immediate safety check
- _"I hurt myself"_ — Log incident, suggest first aid

---

## Tool Integrations

### 1. Torque Spec Lookup

```javascript
// When user asks "What's the torque for this?"
async function getTorqueSpec(make, model, component, boltLocation) {
  const search = await webSearch(
    `${make} ${model} ${component} torque spec ${boltLocation}`,
  );
  return parseTorqueFromResults(search);
}
// Returns: "47 Nm (35 ft-lbs) for the upper mounting bolt"
```

### 2. Wiring Diagram Fetch

```javascript
// When user is confused about wiring
async function getWiringDiagram(system, year, make, model) {
  const url = await findDiagram(system, year, make, model);
  const diagram = await fetchPage(url);
  return summarizeWiring(diagram, system);
}
```

### 3. Parts Compatibility Check

```javascript
// When user shows a part
async function verifyPartCompatibility(partNumber, vehicle) {
  const result = await webSearch(`${partNumber} compatibility ${vehicle}`);
  return {
    compatible: parseCompatibility(result),
    notes: parseWarnings(result),
  };
}
// Returns: "This fits 2015-2017 Civics. Note: Different part for 2-door vs 4-door"
```

### 4. Error Code Interpretation

```javascript
// When user sees a diagnostic code
async function interpretErrorCode(code, domain) {
  const result = await webSearch(`${code} ${domain} meaning troubleshooting`);
  return {
    meaning: parseMeaning(result),
    commonCauses: parseCauses(result),
    fixSteps: parseSteps(result),
  };
}
// Example: "P0420 - Catalyst system efficiency below threshold. Common causes: failing catalytic converter, O2 sensor issues, exhaust leaks"
```

---

## Voice Interaction Design

### Command Patterns

| User Says          | Action                      |
| ------------------ | --------------------------- |
| _"Next step"_      | Advance to next instruction |
| _"Repeat that"_    | Re-read current step        |
| _"What is this?"_  | Identify component in view  |
| _"Why?"_           | Explain reasoning           |
| _"Wait / Stop"_    | Pause guidance              |
| _"I finished"_     | Confirm step completion     |
| _"Go back"_        | Return to previous step     |
| _"Overview"_       | Summarize remaining steps   |
| _"Search for [x]"_ | Web search                  |
| _"Call for help"_  | Send alert with context     |

### Confirmation Patterns

**Explicit Confirmations:**

- "Say 'done' when you've disconnected the battery"

**Implicit Confirmations:**

- "Now remove the 12mm bolt..." (assumes user is following)

**Visual Confirmations:**

- "Show me what you're looking at" (user tilts head to show)

---

## Multi-Step Workflow State

```javascript
// Stored in Firestore
const workflowState = {
  sessionId: "abc123",
  domain: "auto_repair",
  task: "alternator_replacement",
  vehicle: "2015 Honda Civic",
  currentStep: 3,
  totalSteps: 7,
  completedSteps: [1, 2],
  skippedSteps: [],
  safetyAcknowledged: ["battery_disconnect"],
  notes: ["Top bolt was tight, used breaker bar"],
  startTime: Timestamp,
  estimatedRemaining: "35 minutes",
};

// Resume capability
async function resumeWorkflow(sessionId) {
  const state = await firestore.doc(`workflows/${sessionId}`).get();
  return {
    message: `Welcome back. You're on step ${state.currentStep} of ${state.totalSteps}. ${getStepDescription(state.currentStep)}`,
    context: state,
  };
}
```

---

## Edge Cases & Error Handling

### User Gets Stuck

```
User: "This bolt won't come out"

RepairMate: "Try these in order:
1. Spray penetrating oil and wait 2 minutes
2. Try a breaker bar for more leverage
3. If it's rounding, stop—we need to extract it

Which have you tried?"
```

### Wrong Part Identified

```
RepairMate: "That looks like the starter, not the alternator.
The alternator is higher up, with a pulley and belt on it.
Can you look higher in the engine bay?"
```

### User Injured

```
User: "I cut my finger"

RepairMate: "Stop work immediately. Apply pressure with a clean cloth.
If bleeding doesn't stop in 5 minutes, seek medical help.
Do you want me to send your location to emergency contacts?"
```

### Lost Connection

```
Reconnect message: "Connection lost. Last step completed: removing alternator belt.
Next: Remove the top 12mm bolt. Ready to continue?"
```

---

## Implementation Phases

### Phase 1: MVP (Hackathon Scope)

- Single domain (auto_repair)
- 5 common procedures
- Basic safety warnings
- Web search for specs
- Voice in/out via Bluetooth

### Phase 2: Expansion

- 4 domains (auto, electronics, appliances, HVAC)
- 50+ procedures in RAG
- Advanced safety classifier
- Community contribution portal
- Workflow history/sync

### Phase 3: Advanced

- AR overlay hints (if glasses support it)
- Thermal camera integration
- Community knowledge base
- Pro technician marketplace
- Insurance claim integration

---

## Technical Requirements Checklist

| Requirement        | Implementation                         |
| ------------------ | -------------------------------------- |
| ✅ Gemini Live API | Bidi streaming audio + vision          |
| ✅ ADK / GenAI SDK | Agent Development Kit for tool calling |
| ✅ Google Cloud    | Cloud Run + Vertex AI + Firestore      |
| ✅ Multimodal      | Vision (glasses) + Audio (voice)       |
| ✅ Interruptible   | Natural conversation flow              |
| ✅ Deployment      | Cloud Run containers                   |

---

> "Meet RepairMate—the hands-free repair assistant. When you're elbow-deep in an engine, you can't scroll YouTube or read a manual. You need someone who can SEE what you're seeing and SPEAK guidance directly to you."

**Live Demo:**

1. Put on glasses, start "alternator replacement" mode
2. Show engine bay
3. RepairMate speaks first step
4. User asks interrupting question: "Wait, which bolt?"
5. RepairMate answers, then resumes
6. Safety warning: "Stop—the battery is still connected"
7. User unplugs battery
8. Continue to next step

**Closing:**

> "RepairMate. See it. Speak it. Fix it."

---

_Document Version: 1.0_  
_Last Updated: 2026-02-20_  
_For: Gemini Live Agent Challenge Submission_
