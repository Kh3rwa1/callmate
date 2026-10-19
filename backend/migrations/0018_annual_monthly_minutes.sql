-- What an annual plan grants each month, fixed when the year is bought, so a later catalogue change
-- never shrinks a year someone already paid for. Years bought before this column: the catalogue of
-- that time (Starter 1,000, Growth 3,000 minutes a month).
ALTER TABLE usage ADD COLUMN annual_monthly_minutes INTEGER;
UPDATE usage
   SET annual_monthly_minutes = CASE COALESCE(annual_plan_id, plan_id) WHEN 'growth' THEN 3000 ELSE 1000 END
 WHERE annual_until IS NOT NULL;
