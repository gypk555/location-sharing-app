-- Supabase Row Level Security (RLS) Policies for Safety App
-- CRITICAL: These policies MUST be applied to prevent IDOR vulnerabilities
-- Without these, users could access OTHER users' emergency contacts

-- ============================================================================
-- EMERGENCY CONTACTS TABLE
-- ============================================================================

-- Enable RLS on the emergency_contacts table
ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;

-- Force RLS for table owner as well (important for security)
ALTER TABLE emergency_contacts FORCE ROW LEVEL SECURITY;

-- Drop existing policies if any (for clean slate)
DROP POLICY IF EXISTS "Users can view own contacts" ON emergency_contacts;
DROP POLICY IF EXISTS "Users can insert own contacts" ON emergency_contacts;
DROP POLICY IF EXISTS "Users can update own contacts" ON emergency_contacts;
DROP POLICY IF EXISTS "Users can delete own contacts" ON emergency_contacts;

-- Policy: Users can only SELECT their own contacts
CREATE POLICY "Users can view own contacts"
ON emergency_contacts
FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Users can only INSERT contacts for themselves
CREATE POLICY "Users can insert own contacts"
ON emergency_contacts
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only UPDATE their own contacts
CREATE POLICY "Users can update own contacts"
ON emergency_contacts
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only DELETE their own contacts
CREATE POLICY "Users can delete own contacts"
ON emergency_contacts
FOR DELETE
USING (auth.uid() = user_id);

-- ============================================================================
-- LOCATION HISTORY TABLE (if you sync location data)
-- ============================================================================

-- Enable RLS on location_history if it exists
-- ALTER TABLE location_history ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE location_history FORCE ROW LEVEL SECURITY;

-- DROP POLICY IF EXISTS "Users can view own locations" ON location_history;
-- DROP POLICY IF EXISTS "Users can insert own locations" ON location_history;
-- DROP POLICY IF EXISTS "Users can delete own locations" ON location_history;

-- CREATE POLICY "Users can view own locations"
-- ON location_history
-- FOR SELECT
-- USING (auth.uid() = user_id);

-- CREATE POLICY "Users can insert own locations"
-- ON location_history
-- FOR INSERT
-- WITH CHECK (auth.uid() = user_id);

-- CREATE POLICY "Users can delete own locations"
-- ON location_history
-- FOR DELETE
-- USING (auth.uid() = user_id);

-- ============================================================================
-- SOS ALERTS TABLE (if you have one)
-- ============================================================================

-- Enable RLS on sos_alerts if it exists
-- ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE sos_alerts FORCE ROW LEVEL SECURITY;

-- CREATE POLICY "Users can view own alerts"
-- ON sos_alerts
-- FOR SELECT
-- USING (auth.uid() = user_id);

-- CREATE POLICY "Users can insert own alerts"
-- ON sos_alerts
-- FOR INSERT
-- WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify RLS is enabled (run this to check)
SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_tables
WHERE tablename = 'emergency_contacts';

-- List all policies on emergency_contacts
SELECT
    policyname,
    tablename,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'emergency_contacts';
