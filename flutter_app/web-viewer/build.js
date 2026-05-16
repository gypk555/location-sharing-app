#!/usr/bin/env node
/*
 * Build step for the static viewer. Generates config.js from environment
 * variables so NO Supabase values ever live in a committed/source file.
 *
 * Render runs this via the static-site `buildCommand` with SUPABASE_URL
 * and SUPABASE_ANON_KEY injected from the dashboard Environment tab.
 *
 * The values still end up inside the delivered config.js — a browser app
 * MUST receive them, there is no way around that. That is fine: the anon
 * (publishable) key is PUBLIC by design and gated by Postgres RLS, the
 * same key already ships inside the Flutter app. The service_role key is
 * the dangerous one; this script refuses to emit it (see check below).
 *
 * Dependency-free (Node core only) — Render's static build env has Node.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const url = (process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
const anon = (process.env.SUPABASE_ANON_KEY || '').trim();

function fail(msg) {
  console.error('\n[build.js] ' + msg + '\n');
  process.exit(1);
}

if (!url || !anon) {
  fail(
    'SUPABASE_URL and SUPABASE_ANON_KEY must be set as environment ' +
    'variables (Render dashboard -> your service -> Environment). ' +
    'They are intentionally NOT stored in any file.'
  );
}
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
  fail(`SUPABASE_URL does not look like a Supabase URL: "${url}"`);
}

// Safety guard (new key format): Supabase's modern keys are opaque, not
// JWTs. The publishable key is `sb_publishable_...` (client-safe); the
// secret key is `sb_secret_...` and bypasses RLS exactly like the legacy
// service_role key. The JWT decode below can't see inside these, so
// reject the secret prefix explicitly before we get there.
if (/^sb_secret_/i.test(anon)) {
  fail(
    'SUPABASE_ANON_KEY is an sb_secret_... key. That is the SECRET ' +
    '(service) key — it bypasses RLS and must NEVER be delivered to a ' +
    'browser. Use the publishable (sb_publishable_...) or anon key.'
  );
}

// Safety guard: refuse the legacy service_role key. It bypasses RLS
// entirely; shipping it to a browser would expose the whole database.
// Legacy Supabase keys are JWTs whose payload carries a "role" claim.
try {
  const seg = anon.split('.');
  if (seg.length === 3) {
    const payload = JSON.parse(
      Buffer.from(seg[1], 'base64').toString('utf8')
    );
    if (payload.role && payload.role !== 'anon') {
      fail(
        `SUPABASE_ANON_KEY has role="${payload.role}". Only the public ` +
        'anon/publishable key may be used here. NEVER put the ' +
        'service_role key in a browser-delivered file.'
      );
    }
  }
} catch (_) {
  // Not a classic JWT (e.g. the newer sb_publishable_... format) —
  // nothing to decode; the URL+RLS model still applies.
}

const out =
  '// GENERATED at build time from environment variables (build.js).\n' +
  '// Do NOT edit and do NOT commit. Injected by the Render buildCommand.\n' +
  'window.LIVE_SHARE_CONFIG = {\n' +
  '  SUPABASE_URL:      ' + JSON.stringify(url) + ',\n' +
  '  SUPABASE_ANON_KEY: ' + JSON.stringify(anon) + ',\n' +
  '};\n';

fs.writeFileSync(path.join(__dirname, 'config.js'), out);
console.log('[build.js] config.js generated from environment variables.');
