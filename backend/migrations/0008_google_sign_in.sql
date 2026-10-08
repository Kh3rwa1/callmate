-- Google (Firebase Auth) sign-in: a user is identified by firebase_uid; phone stays the
-- business contact number (unverified for Google accounts, still unique per account).
ALTER TABLE users ADD COLUMN firebase_uid TEXT;
ALTER TABLE users ADD COLUMN email TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid);
