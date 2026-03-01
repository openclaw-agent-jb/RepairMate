# RepairMate Backend

Firebase backend for the RepairMate technical repair assistant. Manages repair procedures, user workflows, and safety logs using Firestore.

---

## Overview

This backend provides:

- **Firestore Database** — Stores repair procedures, user workflows, and safety logs
- **Import Script** — Bulk imports repair procedures from JSON seed data
- **Security Rules** — Controls access to procedures (read-only public) and user workflows (authenticated)

---

## Repository Structure

```
backend/
├── .firebaserc              # Firebase project configuration
├── firebase.json            # Firebase services config (Firestore location, rules, indexes)
├── firestore.rules          # Security rules for database access
├── firestore-schema.json    # Database schema documentation
├── firestore.indexes.json   # Firestore composite indexes
├── import-procedures.js     # Node.js script to import repair procedures
├── package.json             # NPM dependencies
└── data/
    └── procedures.json      # Sample repair procedure seed data
```

---

## Prerequisites

- [Node.js](https://nodejs.org/) 18+ installed
- [Firebase CLI](https://firebase.google.com/docs/cli) installed globally:

  ```bash
  npm install -g firebase-tools
  ```

- A Google Cloud/Firebase project with Firestore enabled
- (For production) Service account credentials with Firestore write access

---

## Firebase Setup

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Configure Firebase Project

The `.firebaserc` file is pre-configured with the project ID:

```json
{
  "projects": {
    "default": "repairmate-hackathon-2026"
  }
}
```

**To use your own Firebase project:**

```bash
# Login to Firebase
firebase login

# List your projects
firebase projects:list

# Update .firebaserc with your project ID
```

### 3. Set Up Authentication (Production)

For production imports, you need Google Application Credentials:

**Option A: Service Account Key File**

1. Go to [Firebase Console](https://console.firebase.google.com/) → Project Settings → Service Accounts
2. Click "Generate new private key"
3. Save the JSON file securely
4. Set the environment variable:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
   ```

**Option B: Application Default Credentials (ADC)**

```bash
# Login with application default credentials
gcloud auth application-default login
```

---

## Running the Import Script

The import script (`import-procedures.js`) bulk-imports repair procedures from `data/procedures.json` into the Firestore `procedures` collection.

### Option 1: Production Mode

Uses your live Firebase project (requires `GOOGLE_APPLICATION_CREDENTIALS`):

```bash
npm run import
```

Or directly:

```bash
node import-procedures.js
```

### Option 2: Local Emulator Mode

Uses the Firestore emulator (no credentials required, data is local only):

```bash
npm run import:emulator
```

Or directly:

```bash
node import-procedures.js --emulator
```

**To start the Firestore emulator:**

```bash
firebase emulators:start --only firestore
```

Then access the emulator UI at: <http://localhost:4000/firestore>

### Expected Output

```
RepairMate — Firestore Procedure Importer
Project: repairmate-hackathon-2026
Mode:    production

📋  Found 5 procedure(s) to import

  ✔  Queued: auto-alternator-honda-civic-2015  (auto)
  ✔  Queued: auto-brake-pads-toyota-corolla    (auto)
  ✔  Queued: plumbing-fix-leaky-faucet        (plumbing)
  ...

⏳  Committing batch…

✅  Successfully imported 5 procedure(s) into 'procedures' collection.
```

---

## Firestore Security Rules

| Access Pattern |
| -------------- | ------------------------------------------------ |
| `procedures`   | **Public read** — Anyone can read repair guides  |
| `workflows`    | **Authenticated** — Users only access their own  |
| `safetyLogs`   | **Authenticated create** — Users append own logs |
| `procedures`   | **Public read** — Anyone can read repair guides  |
| `workflows`    | **Authenticated** — Users only access their own  |
| `safetyLogs`   | **Authenticated create** — Users append own logs |
| `safetyLogs`   | **Authenticated create** — Users append own logs |

**Deploy security rules:**

```bash
firebase deploy --only firestore:rules
```

---

## Data Schema

### Procedure Document

```json
{
  "id": "auto-alternator-honda-civic-2015",
  "name": "Alternator Replacement — 2015 Honda Civic",
  "domain": "auto",
  "difficulty": "intermediate",
  "estimatedTime": "45–60 minutes",
  "tools": ["10mm socket", "12mm socket", ...],
  "safetyWarnings": ["Disconnect negative battery terminal..."],
  "steps": [
    {
      "number": 1,
      "title": "Safety Preparation",
      "action": "Disconnect the negative battery terminal",
      "visualCues": "Black cable, minus sign...",
      "safetyWarning": "Prevents short circuits...",
      "commonMistakes": ["Forgetting to disconnect"]
    }
  ],
  "createdAt": "2026-02-20T00:00:00Z",
  "updatedAt": "2026-02-20T00:00:00Z"
}
```

See `firestore-schema.json` for complete schema definitions.

---

## Adding Custom Procedures

To add your own repair procedures:

1. Edit `data/procedures.json` and add new procedure objects following the schema
2. Ensure each procedure has a unique `id` field
3. Re-run the import script:

   ```bash
   npm run import
   ```

**Note:** The import script uses batch writes (atomic operation). If any document fails validation, the entire batch is rejected.

---

## Troubleshooting

### "Seed file not found"

Ensure `data/procedures.json` exists relative to the script location:

```bash
ls backend/data/procedures.json
```

### "Permission denied" errors

- Verify `GOOGLE_APPLICATION_CREDENTIALS` is set for production mode
- Check that the service account has `Cloud Datastore User` role
- Verify Firestore is enabled in your Firebase project

### "Project not found"

Update `.firebaserc` with your actual Firebase project ID:

```json
{
  "projects": {
    "default": "your-project-id"
  }
}
```

### Import partially succeeded

The script warns about procedures without an `id` field but continues importing valid ones. Check the output for specific skipped items.

---

## Deployment

Deploy Firestore rules and indexes to production:

```bash
firebase deploy --only firestore
```

Deploy only rules:

```bash
firebase deploy --only firestore:rules
```

Deploy only indexes:

```bash
firebase deploy --only firestore:indexes
```

---

## Related Documentation

- [`docs/CHALLENGE_GUIDE.md`](../docs/CHALLENGE_GUIDE.md) — Complete technical specification
- [`../README.md`](../README.md) — Project overview and architecture
