ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sos_settings JSONB
    DEFAULT '{"shakeAlertEnabled": true, "sosMessage": null}'::jsonb;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fake_call_settings JSONB
    DEFAULT '{"enabled": true, "callerName": "Mom", "callerNumber": "+12345678900"}'::jsonb;

-- Guard against oversized or malformed JSONB payloads (security fix S-2)
ALTER TABLE public.profiles
  ADD CONSTRAINT sos_settings_max_size
    CHECK (sos_settings IS NULL OR octet_length(sos_settings::text) < 2048);

ALTER TABLE public.profiles
  ADD CONSTRAINT fake_call_settings_max_size
    CHECK (fake_call_settings IS NULL OR octet_length(fake_call_settings::text) < 2048);
