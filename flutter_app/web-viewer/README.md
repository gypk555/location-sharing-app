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
viewer page lives on a normal static host (Netlify or Vercel) instead.

Both hosts are supported: `netlify.toml` and `vercel.json` carry the
same rewrite + security headers. Each host reads only its own file.

## URL shape

```
https://<your-host-domain>/s/<share-token-uuid>
```

`?t=<token>` is also accepted as a fallback so forwarded/edited links
still resolve.

## How config gets in (two models)

The page needs `SUPABASE_URL` + `SUPABASE_ANON_KEY` at runtime via
`window.LIVE_SHARE_CONFIG` (in `config.js`). `config.js` is **gitignored
and never committed** — there are no Supabase values in any source file.
How it's produced depends on where you run:

- **Hosted (Render):** set the two values as **environment variables**
  in the Render dashboard. `build.js` runs at deploy time and generates
  `config.js` from them. Nothing secret is in the repo.
- **Local testing:** `cp config.example.js config.js` once and fill in
  the two values by hand (this local file stays on your machine only).

Both values are public/client-safe — RLS-gated, the same anon key already
ships in the Flutter app. **Never** use the `service_role` key; `build.js`
actively refuses it.

## Deploy to Render (Git-based, secrets stay in env)

Render builds from your Git repo, so the viewer must be committed and
pushed. `render.yaml` lives at the **repository root** (Render only
auto-detects a Blueprint there, not in subfolders); it points `rootDir`
back at this `flutter_app/web-viewer/` folder.

1. Commit & push the repo-root `render.yaml` **and** this
   `web-viewer/` folder (incl. `build.js`) to GitHub.
2. Render dashboard → **New** → **Blueprint** → connect the repo
   `gypk555/location-sharing-app`, pick the branch with this code
   (`flutter-migration` — already set in `render.yaml`).
3. Render detects `render.yaml` and shows the service. It will prompt
   for the two `sync: false` env vars — enter:
   - `SUPABASE_URL` = `https://<your-ref>.supabase.co`
   - `SUPABASE_ANON_KEY` = your **anon** key (not service_role)
4. **Apply / Create**. Render runs `node build.js` (generates
   `config.js` from those env vars), publishes the folder, and assigns
   a URL like `https://live-share-viewer.onrender.com`.

To change keys later: dashboard → service → **Environment** → edit →
redeploy. No code change, nothing in Git.

## Deploy to Netlify Drop (no Git, no signup wall to test)

Netlify Drop deploys the folder as-is, so `config.js` must already
exist locally (the file model above). `build.js`/env vars are not used
on this path.

1. Go to https://app.netlify.com/drop
2. Drag the **`web-viewer/` folder** (the folder itself, not its
   contents) onto the drop zone.
3. It deploys immediately and shows a URL like
   `https://random-name-123.netlify.app`. Note it.
4. Netlify will prompt you to create a free account to *keep* the
   site permanently — do that so the URL is stable. The site is
   live for testing even before you claim it.

`netlify.toml` (in this folder) supplies the `/s/<token>` rewrite and
the security headers automatically.

## Deploy to Vercel (alternative)

1. Go to https://vercel.com/new and drag the `web-viewer/` folder in.
2. Click **Deploy**; note the assigned URL.

Or via CLI:

```bash
npm i -g vercel
cd flutter_app/web-viewer
vercel deploy --prod
```

## Wire the Flutter app to the new URL

In `flutter_app/.env`, add:

```
LIVE_SHARE_BASE_URL=https://your-deploy.netlify.app
```

(Don't include a trailing slash. Use whatever domain your host gave
you — `*.netlify.app` or `*.vercel.app`.) Then in
`lib/core/services/live_location_sharing_service.dart`,
`publicUrlForToken()` reads that env var and builds
`https://your-deploy.netlify.app/s/<token>`. Restart the Flutter app
after changing `.env`.

## Verify

```
https://your-deploy.netlify.app/s/00000000-0000-0000-0000-000000000000
```

You should see a Leaflet map with a "This link isn't valid" overlay
card. That confirms the page is rendering, the static assets are
loading, and supabase-js is reaching your project (it called
`get_live_share` and got `P0001 invalid_token`).

## Security headers

Set in `netlify.toml` / `vercel.json` so the deploy is hardened by
default:

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
| `build.js` | Render build step. Generates `config.js` from env vars; **rejects the service_role key**. No secrets in it. |
| `../../render.yaml` (repo root) | Render Blueprint: static runtime, build cmd, `/s/*` rewrite, security headers. Env vars `sync: false` (set in dashboard). At root because Render only detects it there. |
| `config.example.js` | Template for a local `config.js`. Committed; placeholders only. |
| `config.js` | Generated (Render) or hand-made (local). Holds the URL + anon key. **Gitignored, never committed.** |
| `local-server.js` | Dependency-free local test server (rewrite + headers). Uses the local `config.js`. |
| `netlify.toml` | Netlify routing (`/s/<token>` → index.html) + security headers. |
| `vercel.json` | Same, for Vercel. Each host reads only its own file. |
| `deploy-surge.sh` | One-shot Surge.sh deploy helper. |
| `.gitignore` | Keeps `config.js`, `200.html`, `.vercel/` out of git. |

## Cleanup: remove the old Edge Function

Once the Vercel deploy is live and `publicUrlForToken()` points at it,
the `supabase/functions/live-share/` function is no longer reachable
from any code path. You can delete it via the Supabase dashboard
(Edge Functions → live-share → Delete) or leave it in place — it's
inert. The migration `005_realtime_broadcast.sql` is still needed; it
adds the broadcast triggers the viewer subscribes to.
