// Live-share viewer — runtime configuration.
//
// Copy this file to `config.js` and fill in your Supabase project values.
// Both values are PUBLIC and safe to ship to browsers:
//   - SUPABASE_URL is the project endpoint (visible in every API call).
//   - SUPABASE_ANON_KEY is designed to be exposed to clients; it's gated
//     by RLS policies on the database, not by secrecy.
//
// Do NOT put the service-role key here. That key bypasses RLS.
window.LIVE_SHARE_CONFIG = {
  SUPABASE_URL:      "https://YOUR-REF.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-PUBLISHABLE-OR-ANON-KEY",
};
