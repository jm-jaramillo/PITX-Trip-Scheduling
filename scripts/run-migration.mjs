#!/usr/bin/env node
/**
 * One-off helper to apply supabase/migrations/*.sql (and optionally
 * supabase/seed.sql) directly against the Postgres connection string in
 * DATABASE_URL. Not part of the app itself - just a convenience for local
 * setup when you'd rather not paste SQL into the Supabase SQL Editor.
 *
 * Tracks which files have already been applied in a
 * public._schema_migrations table and skips them on replay. This matters
 * even though every migration is written with IF NOT EXISTS / OR REPLACE
 * guards: those guards make re-creating an object a no-op, but they don't
 * make a file safe to replay once a LATER migration has renamed or dropped
 * a column an EARLIER migration's guarded statement still refers to (e.g.
 * an index on a column that's since been renamed) - Postgres resolves
 * column references during parse/analyze, before the "already exists,
 * skip" check ever runs, so replaying that earlier file fails outright.
 * Skipping already-applied files sidesteps the whole class of problem.
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
  await client.query(`
    create table if not exists public._schema_migrations (
      filename text primary key,
      applied_at timestamptz not null default now()
    )
  `);

  const { rows } = await client.query(
    "select filename from public._schema_migrations"
  );
  const applied = new Set(rows.map((r) => r.filename));

  for (const file of files) {
    if (applied.has(file)) {
      console.log(`Skipping ${file} (already applied)`);
      continue;
    }
    console.log(`Applying ${file}...`);
    const sql = readFileSync(path.join(migrationsDir, file), "utf8");
    await client.query(sql);
    await client.query(
      "insert into public._schema_migrations (filename) values ($1)",
      [file]
    );
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
