#!/usr/bin/env bash
# Deploy the live-share viewer to Surge.sh.
#
# Why Surge: it's a plain static host (no signup form / OAuth — the
# account is created by typing email+password in the terminal on first
# run), and it serves HTML rendered (unlike Supabase Edge Functions,
# which sandbox HTML to browsers).
#
# Usage:
#   ./deploy-surge.sh                 # uses a default subdomain
#   ./deploy-surge.sh my-name.surge.sh
#
# Prereqs: node/npm installed; config.js filled in (see config.example.js).

set -euo pipefail
cd "$(dirname "$0")"

DOMAIN="${1:-safety-live-share.surge.sh}"

# --- sanity checks -------------------------------------------------------
if [ ! -f config.js ]; then
  echo "ERROR: config.js missing. Run: cp config.example.js config.js" >&2
  echo "       then fill in SUPABASE_URL + SUPABASE_ANON_KEY." >&2
  exit 1
fi
if grep -q "YOUR-" config.js; then
  echo "ERROR: config.js still has placeholder values (YOUR-...)." >&2
  exit 1
fi

# --- Surge SPA fallback --------------------------------------------------
# Surge serves 200.html for any path with no matching file, keeping the
# URL intact. That is exactly the /s/<token> rewrite the viewer needs
# (its JS reads window.location.pathname). index.html is the single
# source of truth; 200.html is regenerated here every deploy.
cp index.html 200.html
echo "regenerated 200.html from index.html"

# --- ensure surge is available ------------------------------------------
if ! command -v surge >/dev/null 2>&1; then
  echo "surge not found; installing globally via npm..."
  npm install -g surge
fi

# --- deploy --------------------------------------------------------------
# First ever run prompts for email + password in THIS terminal to create
# a free Surge account. No browser, no credit card.
echo "deploying to https://${DOMAIN} ..."
surge . "${DOMAIN}"

echo ""
echo "Done. Smoke-test:"
echo "  https://${DOMAIN}/s/00000000-0000-0000-0000-000000000000"
echo "Then set in flutter_app/.env (no trailing slash):"
echo "  LIVE_SHARE_BASE_URL=https://${DOMAIN}"
