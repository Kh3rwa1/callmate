-- Migration 0017: the owner's app language (en, hi, bn), so notifications and pushes are written
-- in the language the owner reads the app in. Older rows default to English.
ALTER TABLE businesses ADD COLUMN app_language TEXT NOT NULL DEFAULT 'en';
