ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sos_settings JSONB
    DEFAULT '{"shakeAlertEnabled": true, "sosMessage": null}'::jsonb;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fake_call_settings JSONB
    DEFAULT '{"enabled": true, "callerName": "Mom", "callerNumber": "+1 234 567 8900"}'::jsonb;
