-- =============================================
-- Security Fix: Set search_path on all functions
-- =============================================
-- Issue: Function Search Path Mutable (CVE-2018-1058)
-- Reference: https://supabase.com/docs/guides/database/database-advisors
-- Reference: https://wiki.postgresql.org/wiki/A_Guide_to_CVE-2018-1058:_Protect_Your_Search_Path
--
-- Why this matters:
-- Without a fixed search_path, functions are vulnerable to search path injection attacks.
-- An attacker could create a malicious function in a schema that appears earlier in the
-- search path, hijacking function calls. This is especially critical for SECURITY DEFINER
-- functions which execute with the creator's privileges.
--
-- Why empty string is the MOST SECURE option:
-- Using SET search_path = '' completely eliminates search path attacks because:
-- 1. No schema is searched implicitly - all references must be fully qualified
-- 2. Prevents malicious objects in pg_temp or other schemas from being resolved
-- 3. This is the approach recommended by PostgreSQL security advisories
--
-- Note: All function bodies already use fully qualified names (public.table_name)
-- so this change is safe and requires no code modifications.
--
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/_/sql
-- =============================================

-- Fix handle_updated_at() - Trigger function for auto-updating timestamps
ALTER FUNCTION public.handle_updated_at() SET search_path = '';

-- Fix handle_new_user() - SECURITY DEFINER function (CRITICAL - highest risk)
-- Creates profile on new user signup
ALTER FUNCTION public.handle_new_user() SET search_path = '';

-- Fix ensure_single_primary_contact() - Enforces single primary contact per user
ALTER FUNCTION public.ensure_single_primary_contact() SET search_path = '';

-- Fix check_sos_rate_limit() - Rate limiting for SOS alerts
ALTER FUNCTION public.check_sos_rate_limit() SET search_path = '';

-- Fix get_latest_location(UUID) - Returns user's latest location with permission check
ALTER FUNCTION public.get_latest_location(UUID) SET search_path = '';

-- Fix cleanup_old_locations() - Removes old location history data
ALTER FUNCTION public.cleanup_old_locations() SET search_path = '';

-- Fix expire_location_shares() - Deactivates expired location shares
ALTER FUNCTION public.expire_location_shares() SET search_path = '';

-- =============================================
-- Verification Query
-- =============================================
-- After running the above, execute this to verify all functions have search_path set:
--
-- SELECT
--     n.nspname AS schema,
--     p.proname AS function_name,
--     p.proconfig AS config
-- FROM pg_proc p
-- JOIN pg_namespace n ON p.pronamespace = n.oid
-- WHERE n.nspname = 'public'
-- AND p.proname IN (
--     'handle_updated_at',
--     'handle_new_user',
--     'ensure_single_primary_contact',
--     'check_sos_rate_limit',
--     'get_latest_location',
--     'cleanup_old_locations',
--     'expire_location_shares'
-- );
--
-- Expected: Each function should show {search_path=} in the config column (empty string)
