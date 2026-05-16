#!/usr/bin/env node
/*
 * Local static server for testing the live-share viewer WITHOUT deploying
 * to any host (no account needed). Dependency-free (Node core only).
 *
 * It reproduces what Netlify/Vercel/Surge would do:
 *   - serves files from this folder
 *   - rewrites /s/<token> (any non-file path) to index.html, URL preserved,
 *     so the page's `location.pathname` token parser works
 *   - sends the same security headers as netlify.toml (HSTS skipped: it's
 *     https-only and meaningless/ignored over http)
 *   - binds 0.0.0.0 so a phone on the same Wi-Fi can open the link too
 *
 * Usage:
 *   node local-server.js            # port 8080
 *   node local-server.js 5000       # custom port
 */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = __dirname;
const PORT = parseInt(process.argv[2] || process.env.PORT || '8080', 10);

const CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline' https://esm.sh " +
  "https://unpkg.com; style-src 'self' 'unsafe-inline' https://unpkg.com; " +
  "img-src 'self' data: https://*.tile.openstreetmap.org https://unpkg.com; " +
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co; " +
  "font-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; " +
  "form-action 'none'";

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.map': 'application/json',
};

function securityHeaders(res, contentType) {
  res.setHeader('Content-Type', contentType);
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  res.setHeader('Content-Security-Policy', CSP);
}

function send(res, status, body, contentType) {
  securityHeaders(res, contentType);
  res.writeHead(status);
  res.end(body);
}

const server = http.createServer((req, res) => {
  // Strip query string; decode; block path traversal.
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath.includes('..') || urlPath.includes('\0')) {
    return send(res, 400, 'Bad request', 'text/plain; charset=utf-8');
  }
  if (urlPath === '/') urlPath = '/index.html';

  const filePath = path.join(ROOT, urlPath);

  fs.stat(filePath, (err, stat) => {
    if (!err && stat.isFile()) {
      const ext = path.extname(filePath).toLowerCase();
      const type = TYPES[ext] || 'application/octet-stream';
      securityHeaders(res, type);
      res.writeHead(200);
      fs.createReadStream(filePath).pipe(res);
      return;
    }
    // No matching file -> SPA fallback (this is the /s/<token> rewrite).
    fs.readFile(path.join(ROOT, 'index.html'), (e2, html) => {
      if (e2) return send(res, 500, 'index.html missing', 'text/plain; charset=utf-8');
      send(res, 200, html, 'text/html; charset=utf-8');
    });
  });
});

server.listen(PORT, '0.0.0.0', () => {
  // Find the LAN IP so a phone on the same Wi-Fi can reach it.
  let lan = null;
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const i of ifaces || []) {
      if (i.family === 'IPv4' && !i.internal) { lan = i.address; break; }
    }
    if (lan) break;
  }
  const token = '00000000-0000-0000-0000-000000000000';
  console.log(`\n  Live-share viewer running.\n`);
  console.log(`  Desktop browser (this machine):`);
  console.log(`    http://localhost:${PORT}/s/${token}\n`);
  if (lan) {
    console.log(`  Phone on the SAME Wi-Fi (use this for the app + .env):`);
    console.log(`    http://${lan}:${PORT}/s/${token}\n`);
    console.log(`  -> set in flutter_app/.env (no trailing slash):`);
    console.log(`     LIVE_SHARE_BASE_URL=http://${lan}:${PORT}\n`);
  }
  console.log(`  Ctrl+C to stop.\n`);
});
