#!/usr/bin/env node
/**
 * One-off helper to apply supabase/migrations/*.sql (and optionally
 * supabase/seed.sql) directly against the Postgres connection string in
 * DATABASE_URL. Not part of the app itself - just a convenience for local
 * setup when you'd rather not paste SQL into the Supabase SQL Editor.
 *
 * Usage: DATABASE_URL=postgresql://... node scripts/run-migration.mjs [--seed]
 */
import { readFileSync, readdirSync } from "fs";
import path from "path";
import { Client } from "pg";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("Set DATABASE_URL first.");
  process.exit(1);
}

const root = path.resolve(import.meta.dirname, "..");
const migrationsDir = path.join(root, "supabase", "migrations");
const files = readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort();

const client = new Client({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } });
await client.connect();

try {
  for (const file of files) {
    console.log(`Applying ${file}...`);
    const sql = readFileSync(path.join(migrationsDir, file), "utf8");
    await client.query(sql);
  }

  if (process.argv.includes("--seed")) {
    console.log("Applying seed.sql...");
    const sql = readFileSync(path.join(root, "supabase", "seed.sql"), "utf8");
    await client.query(sql);
  }

  console.log("Done.");
} finally {
  await client.end();
}
