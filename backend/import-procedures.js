#!/usr/bin/env node
/**
 * import-procedures.js
 * Bulk-imports RepairMate seed procedures into Firestore.
 *
 * Usage:
 *   node import-procedures.js            # production (uses GOOGLE_APPLICATION_CREDENTIALS)
 *   node import-procedures.js --emulator  # local Firestore emulator on localhost:8080
 */

"use strict";

const {
  initializeApp,
  cert,
  applicationDefault,
} = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const path = require("path");
const fs = require("fs");

// ── Config ──────────────────────────────────────────────────────────────────
const USE_EMULATOR = process.argv.includes("--emulator");
const PROJECT_ID = "repairmate-hackathon-2026";
const PROCEDURES_PATH = path.join(__dirname, "data", "procedures.json");

// ── Firebase init ────────────────────────────────────────────────────────────
if (USE_EMULATOR) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
  console.log("🔧  Using Firestore emulator at 127.0.0.1:8080");
}

initializeApp({
  credential: USE_EMULATOR
    ? applicationDefault() // emulator ignores auth
    : applicationDefault(), // production: needs GOOGLE_APPLICATION_CREDENTIALS
  projectId: PROJECT_ID,
});

const db = getFirestore();

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Add server timestamps to a procedure document. */
function stampProcedure(procedure) {
  const now = new Date();
  return {
    ...procedure,
    createdAt: procedure.createdAt ? new Date(procedure.createdAt) : now,
    updatedAt: now,
  };
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`\nRepairMate — Firestore Procedure Importer`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Mode:    ${USE_EMULATOR ? "emulator" : "production"}\n`);

  // Load seed data
  if (!fs.existsSync(PROCEDURES_PATH)) {
    console.error(`❌  Seed file not found: ${PROCEDURES_PATH}`);
    process.exit(1);
  }

  const procedures = JSON.parse(fs.readFileSync(PROCEDURES_PATH, "utf8"));
  console.log(`📋  Found ${procedures.length} procedure(s) to import\n`);

  // Use a Firestore batch for atomicity (max 500 writes per batch)
  const batch = db.batch();

  for (const procedure of procedures) {
    if (!procedure.id) {
      console.warn(`⚠️   Skipping procedure with no id: ${procedure.name}`);
      continue;
    }
    const ref = db.collection("procedures").doc(procedure.id);
    batch.set(ref, stampProcedure(procedure));
    console.log(`  ✔  Queued: ${procedure.id}  (${procedure.domain})`);
  }

  console.log("\n⏳  Committing batch…");
  await batch.commit();

  console.log(
    `\n✅  Successfully imported ${procedures.length} procedure(s) into 'procedures' collection.`,
  );
  if (USE_EMULATOR) {
    console.log("    View at: http://localhost:4000/firestore");
  }
}

main().catch((err) => {
  console.error("\n❌  Import failed:", err.message);
  process.exit(1);
});
