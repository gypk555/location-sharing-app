# Live-share viewer (static web page)

Public web page that lets non-app recipients open a live-location share
URL in any browser. Single static `index.html` + a couple of CDN deps
(Leaflet + supabase-js); no build step.

## Why this isn't a Supabase Edge Function

Supabase's gateway intentionally neutralizes HTML responses served from
Edge Functions to real browsers (it rewrites them to
`Content-Type: text/plain` with `Content-Security-Policy: default-src
'none'; sandbox`) to prevent customers from hosting phishing pages on
the shared `*.supabase.co` domain. We can't opt out of that, so the
viewer page lives on Vercel instead.

## URL shape

```
https://<your-vercel-domain>/s/<share-token-uuid>
```

`?t=<token>` is also accepted as a fallback so forwarded/edited links
still resolve.

## One-time setup

1. Copy `config.example.js` to `config.js`:
   ```bash
   cp config.example.js config.js
   ```
2. Edit `config.js` and fill in your project's `SUPABASE_URL` and
   `SUPABASE_ANON_KEY`. Both values are public/client-safe — they're
   gated by RLS, not by secrecy. **Do NOT** put the service-role key
   here.

## Deploy to Vercel (easiest path: drag-and-drop)

1. Go to https://vercel.com/new
2. Drag the `web-viewer/` folder into the upload zone.
3. Click **Deploy**.
4. Note the URL Vercel assigns (e.g. `safety-share-abc123.vercel.app`).

Optional: hook the folder up to a Git repo so future commits redeploy
automatically. Drag-and-drop is fine for one-off testing.

## Deploy via Vercel CLI

```bash
npm i -g vercel
cd flutter_app/web-viewer
vercel deploy --prod
```

## Wire the Flutter app to the new URL

In `flutter_app/.env`, add:

```
LIVE_SHARE_BASE_URL=https://your-deploy.vercel.app
```

(Don't include a trailing slash.) Then in
`lib/core/services/live_location_sharing_service.dart`,
`publicUrlForToken()` reads that env var and builds
`https://your-deploy.vercel.app/s/<token>`. Restart the Flutter app
after changing `.env`.

## Verify

```
https://your-deploy.vercel.app/s/00000000-0000-0000-0000-000000000000
```

You should see a Leaflet map with a "This link isn't valid" overlay
card. That confirms the page is rendering, the static assets are
loading, and supabase-js is reaching your project (it called
`get_live_share` and got `P0001 invalid_token`).

## Security headers

Set in `vercel.json` so the deploy is hardened by default:

- `Cache-Control: no-store` — links shouldn't be cached anywhere.
- `X-Robots-Tag: noindex, nofollow` — leaked links don't get indexed.
- `Referrer-Policy: no-referrer` — outbound clicks don't leak the
  token in `Referer`.
- `X-Frame-Options: DENY`, `frame-ancestors 'none'` — page can't be
  iframed (defeats clickjacking).
- Strict CSP allowing only `'self'`, `esm.sh`, `unpkg.com`,
  `*.tile.openstreetmap.org`, and `*.supabase.co`.

## Files

| File | Purpose |
|---|---|
| `index.html` | The viewer page. Inline JS handles token parsing, RPC fetch, realtime subscription, polling fallback. |
| `config.example.js` | Template for `config.js`. Commit this; not `config.js`. |
| `config.js` | Your project's `SUPABASE_URL` + `SUPABASE_ANON_KEY`. **Gitignored.** |
| `vercel.json` | Routing (`/s/<token>` → index.html) and security headers. |
| `.gitignore` | Keeps `config.js` and `.vercel/` out of git. |

## Cleanup: remove the old Edge Function

Once the Vercel deploy is live and `publicUrlForToken()` points at it,
the `supabase/functions/live-share/` function is no longer reachable
from any code path. You can delete it via the Supabase dashboard
(Edge Functions → live-share → Delete) or leave it in place — it's
inert. The migration `005_realtime_broadcast.sql` is still needed; it
adds the broadcast triggers the viewer subscribes to.
