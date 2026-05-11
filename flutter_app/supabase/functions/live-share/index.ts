// supabase/functions/live-share/index.ts
//
// Public HTML viewer for a single live-location share.
//
// URL contract:   /functions/v1/live-share/<share_token>
// Caller:         any browser, no auth header (the function is deployed
//                 with --no-verify-jwt). The unguessable UUID share_token
//                 in the URL path is the sole authorization mechanism —
//                 same threat model as the get_live_share() RPC.
//
// What this function does:
//   1. Parses <share_token> from the trailing path segment.
//   2. Validates the UUID v4 shape with a regex; returns a static 404
//      "invalid link" HTML page if it doesn't match. Pre-rendered so a
//      bot probing random URLs can't even reach the supabase-js bundle.
//   3. Returns a self-contained HTML page that:
//        a. Renders a Leaflet + OpenStreetMap map (no API key required).
//        b. Calls get_live_share() once on load to populate initial state.
//        c. Subscribes to a private Realtime broadcast channel
//           'share:<token>'. A trigger on location_history (migration 005)
//           publishes 'position' events; a trigger on location_sharing
//           publishes 'share_ended' on revoke/expire.
//        d. Falls back to polling get_live_share() every 5s if no
//           broadcast arrives within 12s (initial connect failure or
//           mid-session WebSocket drop). Watchdog re-arms on every
//           broadcast, so polling and broadcast are mutually exclusive.
//        e. Transitions to a terminal "Sharing has ended" state on
//           share_ended event, P0002 from get_live_share, or expiry
//           countdown reaching zero.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL  = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// UUID v4 regex. We don't enforce the version-4 nibble strictly because
// gen_random_uuid() in Postgres always emits v4, but accepting any UUID
// shape costs nothing and avoids tight coupling to the Postgres version.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Common security headers applied to every HTML response. Notes:
//  - X-Robots-Tag prevents Google/Bing from indexing leaked share links.
//  - Referrer-Policy: no-referrer prevents the share token leaking via
//    Referer headers when the user clicks an outbound link.
//  - X-Frame-Options blocks the page from being framed (clickjacking).
//  - CSP allows: self (default), 'unsafe-inline' for the bootstrap
//    script + inline styles (we don't have a build step to compute
//    nonces), esm.sh + unpkg.com for supabase-js + Leaflet, OSM tile
//    domains for the map images, SUPABASE_URL for REST/RPC, and the
//    matching wss:// origin for Realtime WebSockets.
function commonHeaders(): Record<string, string> {
  const wsOrigin = SUPABASE_URL ? `wss://${new URL(SUPABASE_URL).host}` : "";
  return {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store, max-age=0",
    "X-Robots-Tag": "noindex, nofollow",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "X-Content-Type-Options": "nosniff",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "Content-Security-Policy": [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' https://esm.sh https://unpkg.com",
      "style-src 'self' 'unsafe-inline' https://unpkg.com",
      "img-src 'self' data: https://*.tile.openstreetmap.org https://unpkg.com",
      `connect-src 'self' ${SUPABASE_URL} ${wsOrigin}`.trim(),
      "font-src 'self' data:",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'none'",
    ].join("; "),
  };
}

// Static 404 page for invalid/malformed tokens. No JS, no external deps —
// makes URL-shape probing cheap to serve and prevents bots from probing
// further into the supabase-js bundle.
function notFoundHtml(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Link not valid</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0;
    min-height: 100vh;
    display: grid;
    place-items: center;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f7f7f8;
    color: #1a1a1a;
    padding: 24px;
  }
  .card {
    max-width: 360px;
    text-align: center;
    background: #fff;
    border-radius: 16px;
    padding: 32px 24px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.04);
  }
  h1 { font-size: 20px; margin: 16px 0 8px; }
  p  { margin: 0; color: #6b6b6b; line-height: 1.5; font-size: 15px; }
  .icon {
    width: 56px; height: 56px; border-radius: 50%;
    background: #fde2e2; color: #c62828;
    display: grid; place-items: center; margin: 0 auto;
    font-size: 28px;
  }
  @media (prefers-color-scheme: dark) {
    body { background: #0e0e10; color: #f1f1f1; }
    .card { background: #18181b; box-shadow: none; }
    p { color: #a1a1aa; }
  }
</style>
</head>
<body>
  <div class="card">
    <div class="icon">!</div>
    <h1>This link isn't valid</h1>
    <p>The live-location link you opened is malformed or has expired. Ask the sender for a fresh link.</p>
  </div>
</body>
</html>`;
}

// Main page. The `token` is interpolated into the JS bootstrap object
// after a UUID-shape check, so it's already constrained to [0-9a-f-].
// SUPABASE_URL and SUPABASE_ANON_KEY come from env vars. We still
// JSON.stringify them on the way in as defense in depth — even though
// these values are under our control, treating them like untrusted
// strings means the template stays correct if they ever contain
// characters that would break the JS literal.
function pageHtml(token: string): string {
  const boot = JSON.stringify({
    url: SUPABASE_URL,
    key: SUPABASE_ANON,
    token,
  });

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<title>Live location</title>
<link rel="stylesheet"
      href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
      crossorigin="" />
<style>
  :root {
    color-scheme: light dark;
    --bg: #f5f5f7;
    --panel: #ffffff;
    --text: #18181b;
    --muted: #71717a;
    --border: #e4e4e7;
    --brand: #2563eb;
    --brand-soft: #dbeafe;
    --danger: #c62828;
    --danger-soft: #fde2e2;
    --good: #16a34a;
    --good-soft: #dcfce7;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0a0a0b;
      --panel: #18181b;
      --text: #f4f4f5;
      --muted: #a1a1aa;
      --border: #27272a;
      --brand: #60a5fa;
      --brand-soft: #1e3a8a;
      --danger: #fca5a5;
      --danger-soft: #450a0a;
      --good: #86efac;
      --good-soft: #14532d;
    }
  }

  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: var(--bg); color: var(--text);
    overflow: hidden;
  }

  /* Layout: map fills the screen, panel docks at the top on mobile,
     left sidebar on wider screens. */
  #app { position: fixed; inset: 0; display: grid; grid-template-rows: auto 1fr; }
  #map { width: 100%; height: 100%; background: #ddd; }
  @media (min-width: 720px) {
    #app { grid-template-rows: 1fr; grid-template-columns: 360px 1fr; }
  }

  #panel {
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    padding: 16px 20px;
    display: flex; flex-direction: column; gap: 12px;
    z-index: 500;
  }
  @media (min-width: 720px) {
    #panel { border-bottom: none; border-right: 1px solid var(--border); overflow-y: auto; }
  }

  .header { display: flex; align-items: center; gap: 12px; }
  .avatar {
    width: 44px; height: 44px; border-radius: 50%;
    background: var(--brand-soft); color: var(--brand);
    display: grid; place-items: center;
    font-weight: 600; font-size: 18px; flex-shrink: 0;
  }
  .header-text h1 { font-size: 16px; margin: 0 0 2px; line-height: 1.2; }
  .header-text p  { font-size: 13px; margin: 0; color: var(--muted); }

  .status {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 4px 10px; border-radius: 999px;
    background: var(--good-soft); color: var(--good);
    font-size: 12px; font-weight: 500;
    align-self: flex-start;
  }
  .status .dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: currentColor;
    animation: pulse 1.6s ease-in-out infinite;
  }
  .status[data-state="offline"] { background: var(--danger-soft); color: var(--danger); }
  .status[data-state="offline"] .dot { animation: none; }
  .status[data-state="loading"] { background: var(--border); color: var(--muted); }
  .status[data-state="loading"] .dot { animation: pulse 1s ease-in-out infinite; }
  @keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50%      { opacity: 0.4; transform: scale(0.7); }
  }

  dl.meta {
    margin: 0; display: grid;
    grid-template-columns: auto 1fr; gap: 8px 16px;
    font-size: 14px;
  }
  dl.meta dt { color: var(--muted); }
  dl.meta dd { margin: 0; font-variant-numeric: tabular-nums; }

  /* Custom marker. Filled blue dot with a heading triangle that
     rotates around its center via CSS transform. */
  .marker {
    width: 22px; height: 22px;
    border-radius: 50%;
    background: var(--brand); border: 3px solid #fff;
    box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.18), 0 2px 6px rgba(0,0,0,0.18);
    position: relative;
  }
  .marker .arrow {
    position: absolute; top: -10px; left: 50%;
    width: 0; height: 0;
    border-left: 6px solid transparent;
    border-right: 6px solid transparent;
    border-bottom: 10px solid var(--brand);
    transform: translateX(-50%);
    transform-origin: 50% 16px; /* pivot at the center of the dot */
    transition: transform 0.4s ease-out;
  }
  .marker.no-heading .arrow { display: none; }

  /* Ended overlay covers the whole screen when the share is over. */
  #ended {
    position: fixed; inset: 0;
    background: color-mix(in srgb, var(--bg) 92%, transparent);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: grid; place-items: center;
    padding: 24px; z-index: 1000;
  }
  #ended .card {
    max-width: 360px; text-align: center;
    background: var(--panel);
    border-radius: 16px; padding: 32px 24px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.06);
  }
  #ended .icon {
    width: 56px; height: 56px; border-radius: 50%;
    background: var(--border); color: var(--muted);
    display: grid; place-items: center; margin: 0 auto;
    font-size: 28px;
  }
  #ended h2 { font-size: 20px; margin: 16px 0 8px; }
  #ended p  { margin: 0; color: var(--muted); line-height: 1.5; font-size: 15px; }

  [hidden] { display: none !important; }
</style>
</head>
<body>
  <main id="app">
    <aside id="panel">
      <div class="header">
        <div class="avatar" id="avatar">·</div>
        <div class="header-text">
          <h1 id="owner-name">Loading…</h1>
          <p>is sharing live location</p>
        </div>
      </div>
      <div class="status" id="status" data-state="loading">
        <span class="dot"></span>
        <span id="status-text">Connecting…</span>
      </div>
      <dl class="meta">
        <dt>Last update</dt>  <dd id="last-update">—</dd>
        <dt>Accuracy</dt>     <dd id="accuracy">—</dd>
        <dt>Speed</dt>        <dd id="speed">—</dd>
        <dt>Heading</dt>      <dd id="heading">—</dd>
        <dt>Expires</dt>      <dd id="expiry">—</dd>
      </dl>
    </aside>
    <div id="map" role="application" aria-label="Live location map"></div>
  </main>

  <div id="ended" hidden>
    <div class="card">
      <div class="icon">●</div>
      <h2 id="ended-title">Sharing has ended</h2>
      <p id="ended-body">This live location is no longer being updated.</p>
    </div>
  </div>

  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
          integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
          crossorigin=""></script>
  <script type="module">
    import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

    const BOOT = ${boot};
    const supabase = createClient(BOOT.url, BOOT.key, {
      // Cap event rate to be polite — owner cadence is 5–30s, so 5/sec is
      // already 25× headroom and prevents a runaway loop from melting the
      // browser if a trigger ever misbehaves.
      realtime: { params: { eventsPerSecond: 5 } },
    });

    // ===== DOM refs =====
    const $ownerName  = document.getElementById("owner-name");
    const $avatar     = document.getElementById("avatar");
    const $statusEl   = document.getElementById("status");
    const $statusText = document.getElementById("status-text");
    const $lastUpdate = document.getElementById("last-update");
    const $accuracy   = document.getElementById("accuracy");
    const $speed      = document.getElementById("speed");
    const $heading    = document.getElementById("heading");
    const $expiry     = document.getElementById("expiry");
    const $ended      = document.getElementById("ended");
    const $endedTitle = document.getElementById("ended-title");
    const $endedBody  = document.getElementById("ended-body");

    // ===== state =====
    /** @type {"loading" | "active" | "ended" | "error"} */
    let state = "loading";
    let expiresAt    = null;     // Date | null (null = "until stopped")
    let lastFix      = null;     // last position object
    let lastFixAt    = 0;        // Date.now() of last position
    let pollTimer    = null;
    let watchdogTimer = null;
    let countdownTimer = null;
    let lastUpdateTimer = null;

    // ===== Leaflet =====
    let map = null;
    let marker = null;
    let accuracyCircle = null;
    let userInteracted = false;

    function initMap(lat, lng) {
      map = L.map("map", { zoomControl: true }).setView([lat, lng], 16);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        // OpenStreetMap TOS requires this attribution. Don't hide it.
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      }).addTo(map);
      // The first time the user pans or zooms, stop auto-panning to keep
      // their viewport stable. We'll only intervene if the marker would
      // scroll off-screen.
      map.on("dragstart zoomstart", () => { userInteracted = true; });
    }

    function ensureMarker(lat, lng, heading) {
      const arrow = (heading != null && Number.isFinite(heading))
        ? \`<div class="arrow" style="transform: translateX(-50%) rotate(\${heading}deg)"></div>\`
        : "";
      const html = \`<div class="marker \${heading == null ? 'no-heading' : ''}">\${arrow}</div>\`;
      const icon = L.divIcon({
        className: "",
        html,
        iconSize: [22, 22],
        iconAnchor: [11, 11],
      });
      if (!marker) {
        marker = L.marker([lat, lng], { icon, interactive: false }).addTo(map);
      } else {
        marker.setLatLng([lat, lng]);
        marker.setIcon(icon);
      }
    }

    function ensureAccuracyCircle(lat, lng, accuracy) {
      if (accuracy == null || !Number.isFinite(accuracy)) {
        if (accuracyCircle) { accuracyCircle.remove(); accuracyCircle = null; }
        return;
      }
      if (!accuracyCircle) {
        accuracyCircle = L.circle([lat, lng], {
          radius: accuracy, color: "#2563eb", fillColor: "#2563eb",
          fillOpacity: 0.12, weight: 1, interactive: false,
        }).addTo(map);
      } else {
        accuracyCircle.setLatLng([lat, lng]);
        accuracyCircle.setRadius(accuracy);
      }
    }

    function recenterIfNeeded(lat, lng) {
      if (!map) return;
      if (!userInteracted) {
        map.panTo([lat, lng], { animate: true, duration: 0.4 });
        return;
      }
      // Only nudge when the marker is within 15% of the viewport edge or
      // off-screen. .pad(-0.15) shrinks the bounds, so .contains()
      // returns false when the point is in that outer 15% margin.
      const inner = map.getBounds().pad(-0.15);
      if (!inner.contains([lat, lng])) {
        map.panTo([lat, lng], { animate: true, duration: 0.4 });
      }
    }

    // ===== formatting helpers =====
    function compassDir(deg) {
      if (deg == null || !Number.isFinite(deg)) return null;
      const dirs = ["N","NE","E","SE","S","SW","W","NW"];
      return dirs[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }
    function fmtSpeed(mps) {
      if (mps == null || !Number.isFinite(mps) || mps < 0) return "—";
      if (mps < 0.5) return "Stopped";
      return \`\${(mps * 3.6).toFixed(1)} km/h\`;
    }
    function fmtAccuracy(m) {
      if (m == null || !Number.isFinite(m)) return "—";
      return \`±\${Math.round(m)} m\`;
    }
    function fmtHeading(deg) {
      const d = compassDir(deg);
      if (!d) return "—";
      return \`\${d} (\${Math.round(deg)}°)\`;
    }
    function fmtAge(ms) {
      const s = Math.max(0, Math.floor(ms / 1000));
      if (s < 5)  return "Just now";
      if (s < 60) return \`\${s}s ago\`;
      const m = Math.floor(s / 60);
      if (m < 60) return \`\${m}m ago\`;
      const h = Math.floor(m / 60);
      return \`\${h}h \${m % 60}m ago\`;
    }
    function fmtRemaining(ms) {
      const s = Math.max(0, Math.floor(ms / 1000));
      const h = Math.floor(s / 3600);
      const m = Math.floor((s % 3600) / 60);
      const sec = s % 60;
      if (h > 0) return \`\${h}h \${m}m\`;
      if (m > 0) return \`\${m}m \${String(sec).padStart(2, "0")}s\`;
      return \`\${sec}s\`;
    }
    function initials(name) {
      if (!name) return "·";
      const parts = name.trim().split(/\\s+/).slice(0, 2);
      return parts.map(p => p[0]?.toUpperCase() ?? "").join("") || "·";
    }

    // ===== rendering =====
    function setStatus(stateName, text) {
      $statusEl.dataset.state = stateName;
      $statusText.textContent = text;
    }

    function renderHeader(ownerName) {
      if (ownerName) {
        $ownerName.textContent = ownerName;
        $avatar.textContent = initials(ownerName);
      }
    }

    function render(point) {
      if (state === "ended" || state === "error") return;
      // point: { owner_name?, latitude, longitude, accuracy, speed, heading, location_timestamp }
      if (point.owner_name) renderHeader(point.owner_name);

      const hasFix = point.latitude != null && point.longitude != null;
      if (!hasFix) {
        setStatus("loading", "Waiting for first GPS fix…");
        return;
      }

      const lat = +point.latitude;
      const lng = +point.longitude;
      const acc = point.accuracy != null ? +point.accuracy : null;
      const spd = point.speed    != null ? +point.speed    : null;
      const hdg = point.heading  != null ? +point.heading  : null;
      const ts  = point.location_timestamp ? new Date(point.location_timestamp) : new Date();

      lastFix   = { lat, lng, acc, spd, hdg, ts };
      lastFixAt = Date.now();

      if (!map) initMap(lat, lng);
      ensureMarker(lat, lng, hdg);
      ensureAccuracyCircle(lat, lng, acc);
      recenterIfNeeded(lat, lng);

      setStatus("live", "Live");
      $accuracy.textContent  = fmtAccuracy(acc);
      $speed.textContent     = fmtSpeed(spd);
      $heading.textContent   = fmtHeading(hdg);
      $lastUpdate.textContent = fmtAge(Date.now() - ts.getTime());
      state = "active";
    }

    function setEnded(reason) {
      if (state === "ended") return;
      state = "ended";
      stopPolling();
      if (watchdogTimer) clearTimeout(watchdogTimer);
      if (countdownTimer) clearInterval(countdownTimer);
      if (lastUpdateTimer) clearInterval(lastUpdateTimer);
      const reasonCopy = {
        revoked: "The sharer has stopped sharing their location.",
        expired: "The sharing window has expired.",
        inactive: "This share is no longer active.",
      };
      $endedTitle.textContent = "Sharing has ended";
      $endedBody.textContent  = reasonCopy[reason] || "This live location is no longer being updated.";
      $ended.hidden = false;
    }

    function setError(kind) {
      if (state === "error") return;
      state = "error";
      stopPolling();
      if (watchdogTimer) clearTimeout(watchdogTimer);
      if (countdownTimer) clearInterval(countdownTimer);
      if (lastUpdateTimer) clearInterval(lastUpdateTimer);
      const titleByKind = { invalid: "This link isn't valid" };
      const bodyByKind  = {
        invalid: "The live-location link you opened doesn't match any active share. Ask the sender for a fresh link.",
      };
      $endedTitle.textContent = titleByKind[kind]  || "Something went wrong";
      $endedBody.textContent  = bodyByKind[kind]   || "We couldn't load this live location.";
      $ended.hidden = false;
    }

    // ===== fetch + polling + watchdog =====
    async function fetchOnce() {
      try {
        const { data, error } = await supabase.rpc("get_live_share", { p_token: BOOT.token });
        if (error) {
          // PostgrestError.code carries the Postgres SQLSTATE we set
          // with RAISE EXCEPTION ... USING ERRCODE = 'P000X'.
          if (error.code === "P0001") return setError("invalid");
          if (error.code === "P0002") return setEnded("expired");
          // Network blip / 5xx — leave state alone, polling/watchdog retry.
          return;
        }
        const row = Array.isArray(data) ? data[0] : data;
        if (!row) return setError("invalid");
        if (row.is_active === false) return setEnded("inactive");
        expiresAt = row.expires_at ? new Date(row.expires_at) : null;
        render(row);
      } catch (_e) {
        // Network/transport failure. Same handling as PostgREST 5xx.
      }
    }

    function startPolling() {
      if (pollTimer || state === "ended" || state === "error") return;
      // Run an immediate tick so the UI reacts within ~1s of the
      // watchdog firing, instead of waiting a full poll interval.
      fetchOnce();
      pollTimer = setInterval(fetchOnce, 5000);
      // Visible cue for diagnostics: status pill turns yellow-ish via
      // the "loading" state until we get either a broadcast or a fresh
      // RPC fix. (Happens silently if a fix is already on screen.)
      if (state === "loading") setStatus("loading", "Reconnecting…");
    }
    function stopPolling() {
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    }

    // 12s watchdog: if no broadcast arrives within this window after
    // SUBSCRIBE, or after the last broadcast, switch to polling. Owner
    // cadence is 5s (SOS) or 30s (normal), so 12s lets one normal-tier
    // beat slip without spurious fallback for SOS tier.
    function armWatchdog() {
      if (watchdogTimer) clearTimeout(watchdogTimer);
      watchdogTimer = setTimeout(() => { startPolling(); }, 12000);
    }

    // ===== Realtime broadcast =====
    // Private channel — see migration 005: realtime.send(..., private: true)
    // requires RLS to allow SELECT on realtime.messages for the topic.
    const channel = supabase.channel("share:" + BOOT.token, {
      config: { private: true },
    });

    channel.on("broadcast", { event: "position" }, (msg) => {
      // A successful broadcast means we don't need polling. Re-arm
      // the watchdog so we'll catch the next gap if the WebSocket dies.
      stopPolling();
      armWatchdog();
      render(msg.payload);
    });

    channel.on("broadcast", { event: "share_ended" }, (msg) => {
      setEnded(msg.payload?.reason ?? "inactive");
    });

    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        armWatchdog();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        // RLS denial or transport failure. Fall through to polling.
        startPolling();
      }
    });

    // ===== expiry countdown + last-update tickers =====
    countdownTimer = setInterval(() => {
      if (state === "ended" || state === "error") return;
      if (!expiresAt) {
        $expiry.textContent = "Until stopped";
        return;
      }
      const ms = expiresAt - new Date();
      if (ms <= 0) {
        setEnded("expired");
        return;
      }
      $expiry.textContent = fmtRemaining(ms);
    }, 1000);

    lastUpdateTimer = setInterval(() => {
      if (state === "ended" || state === "error") return;
      if (!lastFixAt) return;
      $lastUpdate.textContent = fmtAge(Date.now() - lastFixAt);
      // Stale fix > 60s with no broadcast or successful poll: hint to
      // the user the connection is degraded. The data on screen is
      // still the last-known position; we don't blank it out.
      if (Date.now() - lastFixAt > 60_000 && state === "active") {
        setStatus("offline", "Connection lost");
      }
    }, 1000);

    // ===== bootstrap =====
    fetchOnce();
  </script>
</body>
</html>`;
}

serve((req: Request) => {
  // Edge Functions only accept GET for an HTML viewer. Reject other
  // methods quickly so misconfigured clients don't get an HTML body
  // they can't parse.
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  // The function is mounted at /functions/v1/live-share/<token>; we
  // care about everything after the function name. Splitting and
  // taking the last non-empty segment is robust to trailing slashes
  // and to local dev (which serves at /live-share/<token> directly).
  const segments = url.pathname.split("/").filter(Boolean);
  const token = segments[segments.length - 1] ?? "";

  // If the path didn't include a token at all (e.g. /functions/v1/live-share),
  // segments will end with "live-share" — treat that as a 404 too.
  const looksLikeToken = token !== "" && token !== "live-share";

  if (!looksLikeToken || !UUID_RE.test(token)) {
    return new Response(notFoundHtml(), { status: 404, headers: commonHeaders() });
  }

  // HEAD: same headers, empty body. Useful for monitoring probes.
  if (req.method === "HEAD") {
    return new Response(null, { status: 200, headers: commonHeaders() });
  }

  return new Response(pageHtml(token), { status: 200, headers: commonHeaders() });
});
